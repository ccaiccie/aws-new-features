data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_a   = data.aws_availability_zones.available.names[0]
  az_b   = data.aws_availability_zones.available.names[1]
  az_ids = zipmap(data.aws_availability_zones.available.names, data.aws_availability_zones.available.zone_ids)

  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Lab       = "2026-11-21-tgw-firewall-context-sharing"
  }
}

# ------------------------------------------------------------------------------
# 1. Development VPC, Subnets, and Security Group
# ------------------------------------------------------------------------------
resource "aws_vpc" "dev" {
  cidr_block           = var.dev_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-dev-vpc"
    Environment = "development"
  })
}

resource "aws_subnet" "dev_private_a" {
  vpc_id            = aws_vpc.dev.id
  cidr_block        = cidrsubnet(var.dev_vpc_cidr, 8, 1)
  availability_zone = local.az_a

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dev-private-a"
  })
}

resource "aws_subnet" "dev_private_b" {
  vpc_id            = aws_vpc.dev.id
  cidr_block        = cidrsubnet(var.dev_vpc_cidr, 8, 2)
  availability_zone = local.az_b

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dev-private-b"
  })
}

resource "aws_security_group" "dev_app" {
  name        = "${var.project_name}-dev-app-sg"
  description = "Security group for development workloads"
  vpc_id      = aws_vpc.dev.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dev-app-sg"
    Tier = "dev-app"
  })
}

# ------------------------------------------------------------------------------
# 2. Production VPC, Subnets, and Tiered Security Groups (Web & DB)
# ------------------------------------------------------------------------------
resource "aws_vpc" "prod" {
  cidr_block           = var.prod_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-prod-vpc"
    Environment = "production"
  })
}

resource "aws_subnet" "prod_web_a" {
  vpc_id            = aws_vpc.prod.id
  cidr_block        = cidrsubnet(var.prod_vpc_cidr, 8, 1)
  availability_zone = local.az_a

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-prod-web-a"
    Tier = "web"
  })
}

resource "aws_subnet" "prod_db_b" {
  vpc_id            = aws_vpc.prod.id
  cidr_block        = cidrsubnet(var.prod_vpc_cidr, 8, 2)
  availability_zone = local.az_b

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-prod-db-b"
    Tier = "database"
  })
}

resource "aws_security_group" "prod_web" {
  name        = "${var.project_name}-prod-web-sg"
  description = "Security group for production web tier"
  vpc_id      = aws_vpc.prod.id

  ingress {
    from_port   = 8080
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.dev_private_a.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-prod-web-sg"
    Tier = "web"
  })
}

resource "aws_security_group" "prod_db" {
  name        = "${var.project_name}-prod-db-sg"
  description = "Security group for production database tier"
  vpc_id      = aws_vpc.prod.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.prod_web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-prod-db-sg"
    Tier = "database"
  })
}

# ------------------------------------------------------------------------------
# 3. AWS Transit Gateway & VPC Attachments
# ------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "this" {
  description                     = "Transit Gateway for context sharing with AWS Network Firewall"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-tgw"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dev" {
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = aws_vpc.dev.id
  subnet_ids                                      = [aws_subnet.dev_private_a.id, aws_subnet.dev_private_b.id]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dev-attach"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "prod" {
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = aws_vpc.prod.id
  subnet_ids                                      = [aws_subnet.prod_web_a.id, aws_subnet.prod_db_b.id]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-prod-attach"
  })
}

# ------------------------------------------------------------------------------
# 4. AWS Network Manager Global Network & Transit Gateway Registration
#    (Prerequisite for creating a Network Manager Context Store)
# ------------------------------------------------------------------------------
resource "aws_networkmanager_global_network" "this" {
  description = "Global network hosting the Transit Gateway for context sharing"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-global-network"
  })
}

resource "aws_networkmanager_transit_gateway_registration" "this" {
  global_network_id   = aws_networkmanager_global_network.this.id
  transit_gateway_arn = aws_ec2_transit_gateway.this.arn
}

# ------------------------------------------------------------------------------
# 5. AWS Network Firewall Rule Group, Policy, and TGW-Attached Firewall
# ------------------------------------------------------------------------------
resource "aws_networkfirewall_rule_group" "segmentation" {
  capacity = 100
  name     = "${var.project_name}-segmentation-rg"
  type     = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "DEV_VPC"
        ip_set {
          definition = [var.dev_vpc_cidr]
        }
      }
      ip_sets {
        key = "PROD_VPC"
        ip_set {
          definition = [var.prod_vpc_cidr]
        }
      }
    }

    rules_source {
      rules_string = <<-EOT
        drop tcp $DEV_VPC any -> $PROD_VPC 8082 (msg:"Lab IP-based negative control"; sid:100001; rev:2;)
      EOT
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-segmentation-rg"
  })
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.project_name}-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_rule_group_reference {
      priority     = 1
      resource_arn = aws_networkfirewall_rule_group.segmentation.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-policy"
  })
}

resource "aws_networkfirewall_firewall" "this" {
  name                = "${var.project_name}-anfw"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  transit_gateway_id  = aws_ec2_transit_gateway.this.id

  availability_zone_mapping {
    availability_zone_id = local.az_ids[local.az_a]
  }

  availability_zone_mapping {
    availability_zone_id = local.az_ids[local.az_b]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-anfw"
  })
}
