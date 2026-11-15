terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.73.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
  fqdn = "${var.service_label}.${var.private_zone_name}"
}

# ---------------------------------------------------------------------------
# Producer VPC: owns the private hosted zone, the target and the resource gateway
# ---------------------------------------------------------------------------
resource "aws_vpc" "producer" {
  cidr_block           = var.producer_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-producer" }
}

resource "aws_subnet" "producer" {
  count             = 2
  vpc_id            = aws_vpc.producer.id
  cidr_block        = cidrsubnet(var.producer_cidr, 8, count.index + 1)
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.name_prefix}-producer-${local.azs[count.index]}" }
}

# ---------------------------------------------------------------------------
# Consumer VPC: no peering, no transit gateway, no routes to the producer
# ---------------------------------------------------------------------------
resource "aws_vpc" "consumer" {
  cidr_block           = var.consumer_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-consumer" }
}

resource "aws_subnet" "consumer" {
  count             = 2
  vpc_id            = aws_vpc.consumer.id
  cidr_block        = cidrsubnet(var.consumer_cidr, 8, count.index + 1)
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.name_prefix}-consumer-${local.azs[count.index]}" }
}

# ---------------------------------------------------------------------------
# Private DNS source: a Route 53 private hosted zone that only the producer VPC resolves
# ---------------------------------------------------------------------------
resource "aws_route53_zone" "private" {
  name = var.private_zone_name

  vpc {
    vpc_id = aws_vpc.producer.id
  }

  tags = { Name = "${var.name_prefix}-phz" }
}

resource "aws_route53_record" "service" {
  zone_id = aws_route53_zone.private.zone_id
  name    = local.fqdn
  type    = "A"
  ttl     = 60
  records = [var.create_instances ? aws_instance.target[0].private_ip : var.target_ip]
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------
resource "aws_security_group" "resource_gateway" {
  name        = "${var.name_prefix}-rgw"
  description = "Resource gateway egress to the target port only"
  vpc_id      = aws_vpc.producer.id
  tags        = { Name = "${var.name_prefix}-rgw" }
}

resource "aws_vpc_security_group_egress_rule" "rgw_to_target" {
  security_group_id = aws_security_group.resource_gateway.id
  description       = "Gateway to the target port inside the producer VPC"
  cidr_ipv4         = var.producer_cidr
  ip_protocol       = "tcp"
  from_port         = var.service_port
  to_port           = var.service_port
}

resource "aws_security_group" "target" {
  name        = "${var.name_prefix}-target"
  description = "Target accepts the service port from the resource gateway"
  vpc_id      = aws_vpc.producer.id
  tags        = { Name = "${var.name_prefix}-target" }
}

resource "aws_vpc_security_group_ingress_rule" "target_from_rgw" {
  security_group_id            = aws_security_group.target.id
  description                  = "Traffic arrives from resource gateway addresses"
  referenced_security_group_id = aws_security_group.resource_gateway.id
  ip_protocol                  = "tcp"
  from_port                    = var.service_port
  to_port                      = var.service_port
}

resource "aws_security_group" "association" {
  name        = "${var.name_prefix}-sn-assoc"
  description = "Which consumer workloads may enter the service network"
  vpc_id      = aws_vpc.consumer.id
  tags        = { Name = "${var.name_prefix}-sn-assoc" }
}

resource "aws_vpc_security_group_ingress_rule" "assoc_from_consumer" {
  security_group_id = aws_security_group.association.id
  description       = "Consumer subnets to the shared service port"
  cidr_ipv4         = var.consumer_cidr
  ip_protocol       = "tcp"
  from_port         = var.service_port
  to_port           = var.service_port
}

resource "aws_security_group" "client" {
  name        = "${var.name_prefix}-client"
  description = "Test client, outbound only"
  vpc_id      = aws_vpc.consumer.id
  tags        = { Name = "${var.name_prefix}-client" }
}

resource "aws_vpc_security_group_egress_rule" "client_all" {
  security_group_id = aws_security_group.client.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# VPC Lattice: resource gateway (IN_VPC), resource configuration, service network
# ---------------------------------------------------------------------------
resource "aws_vpclattice_resource_gateway" "this" {
  name               = "${var.name_prefix}-rgw"
  vpc_id             = aws_vpc.producer.id
  subnet_ids         = aws_subnet.producer[*].id
  security_group_ids = [aws_security_group.resource_gateway.id]
  ip_address_type    = "IPV4"
  # Immutable: changing this value replaces the resource gateway.
  resource_config_dns_resolution = var.dns_resolution
}

resource "aws_vpclattice_resource_configuration" "service" {
  name                        = "${var.name_prefix}-${var.service_label}"
  type                        = "SINGLE"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.this.id
  protocol                    = "TCP"
  port_ranges                 = [tostring(var.service_port)]
  # Immutable: the name consumers dial. Set it at creation.
  custom_domain_name = local.fqdn

  resource_configuration_definition {
    dns_resource {
      domain_name     = local.fqdn
      ip_address_type = "IPV4"
    }
  }

  depends_on = [aws_route53_record.service]
}

resource "aws_vpclattice_service_network" "this" {
  name      = "${var.name_prefix}-sn"
  auth_type = "NONE" # auth policies apply to services, not to resource configurations
}

resource "aws_vpclattice_service_network_resource_association" "service" {
  resource_configuration_identifier = aws_vpclattice_resource_configuration.service.id
  service_network_identifier        = aws_vpclattice_service_network.this.id
  # Owner-side switch: without it, no consumer VPC gets a hosted zone.
  private_dns_enabled = true
}

resource "aws_vpclattice_service_network_vpc_association" "consumer" {
  vpc_identifier             = aws_vpc.consumer.id
  service_network_identifier = aws_vpclattice_service_network.this.id
  security_group_ids         = [aws_security_group.association.id]
  private_dns_enabled        = true

  # Consumer-side switch, fixed at creation. The default VERIFIED_DOMAINS_ONLY
  # silently creates no zone for a private name that has no public TXT proof.
  dns_options {
    private_dns_preference        = var.private_dns_preference
    private_dns_specified_domains = [local.fqdn]
  }

  depends_on = [aws_vpclattice_service_network_resource_association.service]
}

# ---------------------------------------------------------------------------
# Optional test instances (no internet access needed; results go to the console log)
# ---------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023" {
  count = var.create_instances ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "target" {
  count                  = var.create_instances ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023[0].value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.producer[0].id
  vpc_security_group_ids = [aws_security_group.target.id]

  user_data = <<-EOT
    #!/bin/bash
    mkdir -p /srv/www && echo "hello from ${local.fqdn} via VPC Lattice" > /srv/www/index.html
    cd /srv/www && nohup python3 -m http.server ${var.service_port} >/var/log/web.log 2>&1 &
  EOT

  tags = { Name = "${var.name_prefix}-target" }
}

resource "aws_instance" "client" {
  count                  = var.create_instances ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023[0].value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.consumer[0].id
  vpc_security_group_ids = [aws_security_group.client.id]

  user_data = <<-EOT
    #!/bin/bash
    for i in $(seq 1 30); do
      echo "LATTICE-TEST $(date -u +%H:%M:%S) $(getent hosts ${local.fqdn} || echo no-dns)" > /dev/console
      echo "LATTICE-TEST $(curl -s -m 5 http://${local.fqdn}:${var.service_port}/ || echo no-response)" > /dev/console
      sleep 60
    done
  EOT

  tags = { Name = "${var.name_prefix}-client" }

  depends_on = [aws_vpclattice_service_network_vpc_association.consumer]
}
