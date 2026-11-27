data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# -----------------------------------------------------------------------------
# 1. Two-Tier VPC (No NAT Gateway — keeps lab cost minimal)
# -----------------------------------------------------------------------------
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-packet-filter-lab"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "igw-packet-filter-lab"
  }
}

resource "aws_subnet" "public_web" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-public-web"
  }
}

resource "aws_subnet" "private_app" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-private-app"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "rtb-public-web"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_web.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "rtb-private-app"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# 2. Customer-Managed Prefix List (Shared IP ranges in one place)
# -----------------------------------------------------------------------------
resource "aws_ec2_managed_prefix_list" "trusted_admin" {
  name           = "pl-trusted-admin-ranges"
  address_family = "IPv4"
  max_entries    = var.prefix_list_max_entries

  dynamic "entry" {
    for_each = var.trusted_admin_cidrs
    content {
      cidr        = entry.value.cidr
      description = entry.value.description
    }
  }

  tags = {
    Name = "pl-trusted-admin-ranges"
  }
}

# -----------------------------------------------------------------------------
# 3. Stateful Security Groups (ENI-level, allow-only, SG-to-SG referencing)
# -----------------------------------------------------------------------------
resource "aws_security_group" "web" {
  name        = "sg-web-tier"
  description = "Stateful ENI firewall for public web tier referencing managed prefix list"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "sg-web-tier"
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_http_from_pl" {
  security_group_id = aws_security_group.web.id
  description       = "Allow HTTP 80 from customer-managed prefix list"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = aws_ec2_managed_prefix_list.trusted_admin.id
}

resource "aws_vpc_security_group_ingress_rule" "web_ssh_from_pl" {
  security_group_id = aws_security_group.web.id
  description       = "Allow SSH 22 from customer-managed prefix list"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  prefix_list_id    = aws_ec2_managed_prefix_list.trusted_admin.id
}

resource "aws_vpc_security_group_egress_rule" "web_to_app_8080" {
  security_group_id            = aws_security_group.web.id
  description                  = "Allow outbound TCP 8080 only to App tier Security Group"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_security_group" "app" {
  name        = "sg-app-tier"
  description = "Stateful ENI firewall for private app tier referencing sg-web-tier"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "sg-app-tier"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_8080_from_web_sg" {
  security_group_id            = aws_security_group.app.id
  description                  = "Allow TCP 8080 only from instances in sg-web-tier"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.web.id
}

# Notice: sg-app-tier has NO outbound rules, yet return traffic to sg-web-tier
# still succeeds automatically because Security Groups are stateful.

# -----------------------------------------------------------------------------
# 4. Stateless Custom Network ACLs (Subnet-level, numbered allow/deny, ephemeral ports)
#    Note: Network ACLs take CIDR blocks, not managed prefix lists.
# -----------------------------------------------------------------------------
resource "aws_network_acl" "public_web" {
  vpc_id     = aws_vpc.lab.id
  subnet_ids = [aws_subnet.public_web.id]

  tags = {
    Name = "nacl-public-web"
  }
}

# Optional explicit DENY at rule 90 (evaluated BEFORE rule 100 ALLOW)
resource "aws_network_acl_rule" "public_in_deny_test" {
  count          = var.block_test_cidr != "" ? 1 : 0
  network_acl_id = aws_network_acl.public_web.id
  rule_number    = 90
  egress         = false
  protocol       = "6"
  rule_action    = "deny"
  cidr_block     = var.block_test_cidr
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public_web.id
  rule_number    = 100
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_in_ssh" {
  network_acl_id = aws_network_acl.public_web.id
  rule_number    = 110
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 22
  to_port        = 22
}

# Inbound ephemeral ports for return traffic from private app tier (32768-61000 on Amazon Linux, 1024-65535 general)
resource "aws_network_acl_rule" "public_in_ephemeral_from_app" {
  network_acl_id = aws_network_acl.public_web.id
  rule_number    = 120
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 1024
  to_port        = 65535
}

# Outbound to private app tier on TCP 8080
resource "aws_network_acl_rule" "public_out_to_app" {
  network_acl_id = aws_network_acl.public_web.id
  rule_number    = 100
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 8080
  to_port        = 8080
}

# Outbound ephemeral ports for return traffic to internet clients (toggle to prove stateless behavior)
resource "aws_network_acl_rule" "public_out_ephemeral" {
  count          = var.enable_ephemeral_outbound_nacl ? 1 : 0
  network_acl_id = aws_network_acl.public_web.id
  rule_number    = 140
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl" "private_app" {
  vpc_id     = aws_vpc.lab.id
  subnet_ids = [aws_subnet.private_app.id]

  tags = {
    Name = "nacl-private-app"
  }
}

resource "aws_network_acl_rule" "private_in_8080_from_web" {
  network_acl_id = aws_network_acl.private_app.id
  rule_number    = 100
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidr
  from_port      = 8080
  to_port        = 8080
}

resource "aws_network_acl_rule" "private_out_ephemeral_to_web" {
  network_acl_id = aws_network_acl.private_app.id
  rule_number    = 100
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidr
  from_port      = 1024
  to_port        = 65535
}

# -----------------------------------------------------------------------------
# 5. Low-Cost Compute (t3.micro, built-in python3 HTTP servers — no NAT needed)
# -----------------------------------------------------------------------------
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_web.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
              #!/bin/bash
              mkdir -p /var/www/html
              echo "WEB-TIER OK (port 80) - Stateful SG + Stateless NACL passed" > /var/www/html/index.html
              nohup python3 -m http.server 80 --directory /var/www/html >/var/log/web.log 2>&1 &
              EOF

  tags = {
    Name = "ec2-public-web"
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private_app.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash
              mkdir -p /var/www/app
              echo "APP-TIER OK (port 8080) - Reached via SG-to-SG reference" > /var/www/app/index.html
              nohup python3 -m http.server 8080 --directory /var/www/app >/var/log/app.log 2>&1 &
              EOF

  tags = {
    Name = "ec2-private-app"
  }
}

# -----------------------------------------------------------------------------
# 6. VPC Flow Logs (CloudWatch Logs, 1-day retention for ACCEPT/REJECT proof)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/packet-filter-lab-flow-logs"
  retention_in_days = 1
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "role-vpc-packet-filter-lab-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "policy-vpc-packet-filter-lab-flow-logs"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  count                    = var.enable_flow_logs ? 1 : 0
  vpc_id                   = aws_vpc.lab.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = {
    Name = "fl-packet-filter-lab"
  }
}
