data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# ---------------------------------------------------------------- VPC: two private subnets in two AZs
# No internet gateway and no public IPs: all traffic stays inside the Region.
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "client" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = local.azs[0]

  tags = {
    Name = "${var.name_prefix}-client-${local.azs[0]}"
    Tier = "web"
  }
}

resource "aws_subnet" "server" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = local.azs[1]

  tags = {
    Name = "${var.name_prefix}-server-${local.azs[1]}"
    Tier = "db"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.name_prefix}-private"
  }
}

resource "aws_route_table_association" "client" {
  subnet_id      = aws_subnet.client.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "server" {
  subnet_id      = aws_subnet.server.id
  route_table_id = aws_route_table.private.id
}

# S3 gateway endpoint: gives the client an AZ-to-service path (AZ-Service-AZ) to Amazon S3.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.lab.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.name_prefix}-s3-gateway"
  }
}

# ---------------------------------------------------------------- Security groups
resource "aws_security_group" "client" {
  name        = "${var.name_prefix}-client"
  description = "Lab client: egress only"
  vpc_id      = aws_vpc.lab.id

  egress {
    description = "All outbound (server in the other AZ, S3 through the gateway endpoint)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "server" {
  name        = "${var.name_prefix}-server"
  description = "Lab server: HTTP 8080 and ICMP echo from the client"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "HTTP from the client"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.client.id]
  }

  ingress {
    description     = "ICMP echo from the client"
    from_port       = 8
    to_port         = 0
    protocol        = "icmp"
    security_groups = [aws_security_group.client.id]
  }

  egress {
    description = "Replies"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
}

# ---------------------------------------------------------------- Instances that create traffic
# Performance Monitor only shows paths with observed traffic, so the client keeps
# TCP (HTTP 8080), ICMP and S3 traffic flowing all the time.
resource "aws_instance" "server" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.server.id
  vpc_security_group_ids = [aws_security_group.server.id]

  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOT
    #!/bin/bash
    mkdir -p /srv/lab && cd /srv/lab
    head -c 262144 /dev/urandom > blob.bin
    echo "npm-lab server" > index.html
    nohup python3 -m http.server 8080 --directory /srv/lab >/var/log/lab-http.log 2>&1 &
  EOT

  tags = {
    Name = "${var.name_prefix}-server"
    Tier = "db"
  }
}

resource "aws_instance" "client" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.client.id
  vpc_security_group_ids = [aws_security_group.client.id]

  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOT
    #!/bin/bash
    cat > /usr/local/bin/lab-traffic.sh <<'SH'
    #!/bin/bash
    while true; do
      curl -s -o /dev/null --max-time 5 http://${aws_instance.server.private_ip}:8080/blob.bin
      ping -c 3 -W 1 ${aws_instance.server.private_ip} >/dev/null
      curl -s -o /dev/null --max-time 5 https://s3.${var.region}.amazonaws.com/
      sleep 5
    done
    SH
    chmod +x /usr/local/bin/lab-traffic.sh
    nohup /usr/local/bin/lab-traffic.sh >/dev/null 2>&1 &
  EOT

  tags = {
    Name = "${var.name_prefix}-client"
    Tier = "web"
  }
}
