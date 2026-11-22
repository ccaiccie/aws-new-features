data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------------------------
# Networking: VPC, Private Subnets, and Security Group
# ------------------------------------------------------------------------------
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.subnet_cidrs)
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.name_prefix}-private-${count.index + 1}"
  }
}

resource "aws_security_group" "lattice_assoc" {
  name        = "${var.name_prefix}-lattice-assoc-sg"
  description = "Controls traffic from the lab VPC to the VPC Lattice service network"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "Allow HTTPS from within the lab VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Allow HTTP from within the lab VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-lattice-assoc-sg"
  }
}

# ------------------------------------------------------------------------------
# VPC Lattice Service Network & VPC Association
# ------------------------------------------------------------------------------
resource "aws_vpclattice_service_network" "main" {
  name      = "${var.name_prefix}-sn"
  auth_type = "AWS_IAM"

  tags = {
    Name = "${var.name_prefix}-sn"
  }
}

resource "aws_vpclattice_service_network_vpc_association" "lab_vpc" {
  vpc_identifier             = aws_vpc.lab.id
  service_network_identifier = aws_vpclattice_service_network.main.id
  security_group_ids         = [aws_security_group.lattice_assoc.id]

  tags = {
    Name = "${var.name_prefix}-vpc-assoc"
  }
}

# ------------------------------------------------------------------------------
# VPC Lattice Service, Target Groups, and Listener + Rules
# ------------------------------------------------------------------------------
resource "aws_vpclattice_service" "orders" {
  name      = "${var.name_prefix}-orders-svc"
  auth_type = "AWS_IAM"

  tags = {
    Name = "${var.name_prefix}-orders-svc"
  }
}

resource "aws_vpclattice_service_network_service_association" "orders" {
  service_identifier         = aws_vpclattice_service.orders.id
  service_network_identifier = aws_vpclattice_service_network.main.id
}

resource "aws_vpclattice_target_group" "orders_v1" {
  name = "${var.name_prefix}-orders-v1"
  type = "IP"

  config {
    port             = 8080
    protocol         = "HTTP"
    protocol_version = "HTTP1"
    vpc_identifier   = aws_vpc.lab.id
    ip_address_type  = "IPV4"

    health_check {
      enabled                       = true
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 2
      path                          = "/health"
      protocol                      = "HTTP"
      protocol_version              = "HTTP1"

      matcher {
        value = "200"
      }
    }
  }

  tags = {
    Name = "${var.name_prefix}-orders-v1"
  }
}

resource "aws_vpclattice_target_group" "orders_v2" {
  name = "${var.name_prefix}-orders-v2"
  type = "IP"

  config {
    port             = 8080
    protocol         = "HTTP"
    protocol_version = "HTTP1"
    vpc_identifier   = aws_vpc.lab.id
    ip_address_type  = "IPV4"

    health_check {
      enabled                       = true
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 2
      path                          = "/health"
      protocol                      = "HTTP"
      protocol_version              = "HTTP1"

      matcher {
        value = "200"
      }
    }
  }

  tags = {
    Name = "${var.name_prefix}-orders-v2"
  }
}

resource "aws_vpclattice_listener" "https" {
  name               = "https-443"
  protocol           = "HTTPS"
  port               = 443
  service_identifier = aws_vpclattice_service.orders.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.orders_v1.id
        weight                  = 90
      }
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.orders_v2.id
        weight                  = 10
      }
    }
  }
}

resource "aws_vpclattice_listener_rule" "canary_header" {
  name                = "canary-header-rule"
  listener_identifier = aws_vpclattice_listener.https.listener_id
  service_identifier  = aws_vpclattice_service.orders.id
  priority            = 10

  match {
    http_match {
      method = "GET"
      path_match {
        case_sensitive = false
        match {
          prefix = "/v2/"
        }
      }
    }
  }

  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.orders_v2.id
        weight                  = 100
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Defense-in-Depth Auth Policies (Service Network + Service)
# ------------------------------------------------------------------------------
resource "aws_vpclattice_auth_policy" "service_network" {
  resource_identifier = aws_vpclattice_service_network.main.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "vpc-lattice-svcs:Invoke"
        Resource  = "*"
        Condition = var.allowed_org_id != "" ? {
          StringEquals = {
            "aws:PrincipalOrgID" = var.allowed_org_id
          }
          } : {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_vpclattice_auth_policy" "orders_service" {
  resource_identifier = aws_vpclattice_service.orders.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "vpc-lattice-svcs:Invoke"
        Resource  = "*"
        Condition = {
          StringEquals = {
            "vpc-lattice-svcs:RequestMethod" = ["GET", "POST"]
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Observability: Access Logs to CloudWatch Logs
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lattice_access" {
  name              = "/aws/vpclattice/${var.name_prefix}"
  retention_in_days = 7
}

resource "aws_vpclattice_access_log_subscription" "service_network" {
  resource_identifier = aws_vpclattice_service_network.main.arn
  destination_arn     = aws_cloudwatch_log_group.lattice_access.arn
}

# ------------------------------------------------------------------------------
# Optional Cross-Account Sharing with AWS RAM
# ------------------------------------------------------------------------------
resource "aws_ram_resource_share" "lattice" {
  count                     = var.enable_ram_share ? 1 : 0
  name                      = "${var.name_prefix}-ram-share"
  allow_external_principals = false
}

resource "aws_ram_resource_association" "service_network" {
  count              = var.enable_ram_share ? 1 : 0
  resource_arn       = aws_vpclattice_service_network.main.arn
  resource_share_arn = aws_ram_resource_share.lattice[0].arn
}

resource "aws_ram_principal_association" "consumers" {
  count              = var.enable_ram_share ? length(var.ram_principal_account_ids) : 0
  principal          = var.ram_principal_account_ids[count.index]
  resource_share_arn = aws_ram_resource_share.lattice[0].arn
}
