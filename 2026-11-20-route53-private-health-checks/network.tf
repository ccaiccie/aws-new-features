# Lab VPC: three private subnets in three AZs, no internet gateway, no NAT.
# A health check source needs one subnet in each of three Availability Zones.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  az_ids   = slice(data.aws_availability_zones.available.zone_ids, 0, 3)
  primary  = cidrhost(aws_subnet.private[0].cidr_block, 10)
  standby  = cidrhost(aws_subnet.private[1].cidr_block, 10)
  app_fqdn = "${var.record_name}.${var.zone_name}"
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # required: domain-name checks resolve through the VPC Route 53 Resolver
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1) # 10.20.1.0/24, 10.20.2.0/24, 10.20.3.0/24
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-private-${local.azs[count.index]}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Security groups -------------------------------------------------------
# Docs: security groups and network ACLs must allow traffic from the health
# check source to the targets; the source's own SGs must allow outbound to them.

resource "aws_security_group" "hc_source" {
  name        = "${var.name}-hc-source"
  description = "Attached to the Route 53 health check source ENIs"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name}-hc-source" }
}

resource "aws_vpc_security_group_egress_rule" "hc_source_to_app" {
  security_group_id            = aws_security_group.hc_source.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "Health checks to the web servers"
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Primary and secondary web servers"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_hc_source" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.hc_source.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "Route 53 private endpoint health checks"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_client" {
  count                        = var.enable_test_client ? 1 : 0
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.client[0].id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "Test client curl"
}
