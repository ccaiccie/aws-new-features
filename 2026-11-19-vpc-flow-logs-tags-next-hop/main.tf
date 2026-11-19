# VPC Flow Logs version 11: EC2 resource tag fields and next-hop fields, in a small VPC
# with a NAT gateway and two tagged instances that generate accepted and rejected traffic.

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  az = data.aws_availability_zones.available.names[0]

  # Custom record format. Order matters: the Logs Insights queries below parse fields by position.
  flow_fields = [
    "version", "account-id", "interface-id", "srcaddr", "dstaddr", "srcport", "dstport", "protocol",
    "packets", "bytes", "start", "end", "action", "log-status",                              # version 2
    "vpc-id", "subnet-id", "instance-id", "tcp-flags", "type", "pkt-srcaddr", "pkt-dstaddr", # version 3
    "az-id",                                                                                 # version 4
    "flow-direction", "traffic-path",                                                        # version 5
    "reject-reason",                                                                         # version 8
    "interface-type", "instance-tag", "instance-tag-2", "interface-tag",                     # version 11
    "next-hop-interface-id", "next-hop-subnet-id", "next-hop-az-id", "next-hop-vpc-id", "next-hop-interface-type",
  ]
  log_format = join(" ", [for f in local.flow_fields : "$${${f}}"])

  # Logs Insights: one "*" per field, field names with underscores instead of hyphens.
  # start, end and type are renamed so they never clash with query keywords.
  renames   = { "start" = "flow_start", "end" = "flow_end", "type" = "ip_type" }
  parse_cmd = "parse @message \"${join(" ", [for f in local.flow_fields : "*"])}\" as ${join(", ", [for f in local.flow_fields : lookup(local.renames, f, replace(f, "-", "_"))])}"
}

# ---------------- network ----------------
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone = local.az
  tags              = { Name = "${var.name}-public" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = local.az
  tags              = { Name = "${var.name}-private" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "${var.name}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.name}-private-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ---------------- security groups ----------------
resource "aws_security_group" "web" {
  name        = "${var.name}-web"
  description = "Web tier: no inbound, all outbound"
  vpc_id      = aws_vpc.lab.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "DB tier: only TCP 8080 from the web tier, so TCP 22 from web is REJECTED"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "App port from the web tier only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- instances (Session Manager, no SSH keys) ----------------
resource "aws_iam_role" "ssm" {
  name = "${var.name}-ssm"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name}-ssm"
  role = aws_iam_role.ssm.name
}

resource "aws_instance" "db" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.db.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data = <<-EOT
    #!/bin/bash
    mkdir -p /srv/www && echo "db tier ok" > /srv/www/index.html
    systemd-run --unit flowlab-http --working-directory=/srv/www /usr/bin/python3 -m http.server 8080
  EOT

  tags = {
    Name = "${var.name}-db"
    app  = "orders-db" # first instance tag key  -> $${instance-tag}
    team = "payments"  # second instance tag key -> $${instance-tag-2}
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  # Every 30 seconds: HTTPS to the internet through the NAT gateway (ACCEPT),
  # TCP 8080 to the db tier (ACCEPT) and TCP 22 to the db tier (REJECT by the db security group).
  user_data = <<-EOT
    #!/bin/bash
    cat > /usr/local/bin/flowlab-traffic.sh <<'SCRIPT'
    #!/bin/bash
    while true; do
      curl -s -o /dev/null --max-time 5 https://checkip.amazonaws.com
      curl -s -o /dev/null --max-time 5 http://${aws_instance.db.private_ip}:8080/
      timeout 3 bash -c "echo > /dev/tcp/${aws_instance.db.private_ip}/22" 2>/dev/null
      sleep 30
    done
    SCRIPT
    chmod +x /usr/local/bin/flowlab-traffic.sh
    systemd-run --unit flowlab-traffic /usr/local/bin/flowlab-traffic.sh
  EOT

  tags = {
    Name = "${var.name}-web"
    app  = "orders-web"
    team = "payments"
  }

  depends_on = [aws_nat_gateway.nat, aws_route_table_association.private]
}

# Network interface tags -> $${interface-tag}
resource "aws_ec2_tag" "web_eni_role" {
  resource_id = aws_instance.web.primary_network_interface_id
  key         = "role"
  value       = "frontend"
}

resource "aws_ec2_tag" "db_eni_role" {
  resource_id = aws_instance.db.primary_network_interface_id
  key         = "role"
  value       = "database"
}

# ---------------- flow log to CloudWatch Logs ----------------
resource "aws_cloudwatch_log_group" "flow" {
  name              = "/vpc-flow-logs/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "flow" {
  name = "${var.name}-flowlogs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow" {
  name = "deliver-to-log-group"
  role = aws_iam_role.flow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = ["${aws_cloudwatch_log_group.flow.arn}", "${aws_cloudwatch_log_group.flow.arn}:*"]
    }]
  })
}

resource "aws_flow_log" "cwl" {
  vpc_id                   = aws_vpc.lab.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow.arn
  iam_role_arn             = aws_iam_role.flow.arn
  max_aggregation_interval = var.aggregation_interval
  log_format               = local.log_format

  # Version 11: up to two tag keys per resource type, position decides the field.
  tag_field_specification {
    resource_type = "instance"
    tag_keys      = ["app", "team"] # instance-tag, instance-tag-2
  }

  tag_field_specification {
    resource_type = "network-interface"
    tag_keys      = ["role"] # interface-tag
  }

  tags = { Name = "${var.name}-cwl" }
}

# ---------------- saved Logs Insights queries ----------------
resource "aws_cloudwatch_query_definition" "rejects_by_tag" {
  name            = "${var.name}/1-rejects-by-tag"
  log_group_names = [aws_cloudwatch_log_group.flow.name]
  query_string    = <<-EOT
    ${local.parse_cmd}
    | filter action = "REJECT"
    | stats count(*) as rejects by instance_tag, interface_tag, srcaddr, dstport, reject_reason
    | sort rejects desc
  EOT
}

resource "aws_cloudwatch_query_definition" "next_hops" {
  name            = "${var.name}/2-egress-next-hops"
  log_group_names = [aws_cloudwatch_log_group.flow.name]
  query_string    = <<-EOT
    ${local.parse_cmd}
    | filter flow_direction = "egress"
    | stats sum(bytes) as bytes_out, count(*) as records by instance_tag, traffic_path, next_hop_interface_type, az_id, next_hop_az_id
    | sort bytes_out desc
  EOT
}

resource "aws_cloudwatch_query_definition" "nat_view" {
  name            = "${var.name}/3-nat-gateway-original-addresses"
  log_group_names = [aws_cloudwatch_log_group.flow.name]
  query_string    = <<-EOT
    ${local.parse_cmd}
    | filter interface_type = "nat_gateway"
    | fields @timestamp, flow_direction, srcaddr, dstaddr, pkt_srcaddr, pkt_dstaddr, traffic_path, bytes
    | sort @timestamp desc
    | limit 50
  EOT
}

# ---------------- optional: same records to S3 as Parquet ----------------
resource "aws_s3_bucket" "flow" {
  count         = var.enable_s3_parquet ? 1 : 0
  bucket_prefix = "${var.name}-flowlogs-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "flow" {
  count                   = var.enable_s3_parquet ? 1 : 0
  bucket                  = aws_s3_bucket.flow[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "flow" {
  count  = var.enable_s3_parquet ? 1 : 0
  bucket = aws_s3_bucket.flow[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.flow[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id, "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.flow[0].arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.flow]
}

resource "aws_flow_log" "s3" {
  count                    = var.enable_s3_parquet ? 1 : 0
  vpc_id                   = aws_vpc.lab.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.flow[0].arn
  max_aggregation_interval = var.aggregation_interval
  log_format               = local.log_format

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }

  tag_field_specification {
    resource_type = "instance"
    tag_keys      = ["app", "team"]
  }

  tag_field_specification {
    resource_type = "network-interface"
    tag_keys      = ["role"]
  }

  tags       = { Name = "${var.name}-s3-parquet" }
  depends_on = [aws_s3_bucket_policy.flow]
}
