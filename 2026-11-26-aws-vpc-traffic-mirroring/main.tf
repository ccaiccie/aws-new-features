data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet"
  }
}

resource "aws_route_table" "lab" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "${var.project_name}-rt"
  }
}

resource "aws_route_table_association" "lab" {
  subnet_id      = aws_subnet.lab.id
  route_table_id = aws_route_table.lab.id
}

# Security group for the monitored source instance
resource "aws_security_group" "source" {
  name        = "${var.project_name}-source-sg"
  description = "Allow test HTTP/HTTPS/SSH/ICMP from operator CIDR"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "HTTP test traffic from operator"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "HTTPS test traffic from operator"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "ICMP echo test from operator"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-source-sg"
  }
}

# Security group for the monitoring target appliance (must allow VXLAN UDP 4789 from source)
resource "aws_security_group" "target" {
  name        = "${var.project_name}-target-sg"
  description = "Allow VXLAN UDP 4789 from mirror source and SSH from operator"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "VXLAN mirrored traffic from source ENI"
    from_port       = 4789
    to_port         = 4789
    protocol        = "udp"
    security_groups = [aws_security_group.source.id]
  }

  ingress {
    description = "SSH from operator for packet inspection"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "Allow outbound updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-target-sg"
  }
}

resource "aws_instance" "source" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.lab.id
  vpc_security_group_ids      = [aws_security_group.source.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-source"
  }
}

resource "aws_instance" "target" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.lab.id
  vpc_security_group_ids      = [aws_security_group.target.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y tcpdump
  EOF

  tags = {
    Name = "${var.project_name}-target"
  }
}

# 1. Traffic Mirror Target (monitoring appliance ENI)
resource "aws_ec2_traffic_mirror_target" "appliance" {
  description          = "Monitoring appliance ENI target"
  network_interface_id = aws_instance.target.primary_network_interface_id

  tags = {
    Name = "${var.project_name}-target"
  }
}

# 2. Traffic Mirror Filter (accept TCP 80 and TCP 443; omit/reject other flows)
resource "aws_ec2_traffic_mirror_filter" "web_only" {
  description = "Mirror TCP 80 and TCP 443 traffic only"

  tags = {
    Name = "${var.project_name}-filter-web"
  }
}

resource "aws_ec2_traffic_mirror_filter_rule" "ingress_http" {
  description              = "Accept inbound HTTP (TCP 80)"
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.web_only.id
  traffic_direction        = "ingress"
  rule_number              = 100
  rule_action              = "accept"
  protocol                 = 6
  source_cidr_block        = "0.0.0.0/0"
  destination_cidr_block   = "0.0.0.0/0"

  destination_port_range {
    from_port = 80
    to_port   = 80
  }
}

resource "aws_ec2_traffic_mirror_filter_rule" "ingress_https" {
  description              = "Accept inbound HTTPS (TCP 443)"
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.web_only.id
  traffic_direction        = "ingress"
  rule_number              = 110
  rule_action              = "accept"
  protocol                 = 6
  source_cidr_block        = "0.0.0.0/0"
  destination_cidr_block   = "0.0.0.0/0"

  destination_port_range {
    from_port = 443
    to_port   = 443
  }
}

resource "aws_ec2_traffic_mirror_filter_rule" "egress_http" {
  description              = "Accept outbound HTTP (TCP 80)"
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.web_only.id
  traffic_direction        = "egress"
  rule_number              = 100
  rule_action              = "accept"
  protocol                 = 6
  source_cidr_block        = "0.0.0.0/0"
  destination_cidr_block   = "0.0.0.0/0"

  destination_port_range {
    from_port = 80
    to_port   = 80
  }
}

resource "aws_ec2_traffic_mirror_filter_rule" "egress_https" {
  description              = "Accept outbound HTTPS (TCP 443)"
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.web_only.id
  traffic_direction        = "egress"
  rule_number              = 110
  rule_action              = "accept"
  protocol                 = 6
  source_cidr_block        = "0.0.0.0/0"
  destination_cidr_block   = "0.0.0.0/0"

  destination_port_range {
    from_port = 443
    to_port   = 443
  }
}

# 3. Traffic Mirror Session (connects source ENI, filter, and target)
# BILLING WARNING: Each active traffic mirror session is billed hourly until deleted.
resource "aws_ec2_traffic_mirror_session" "lab" {
  description              = "Mirror TCP 80/443 from source ENI to appliance ENI"
  network_interface_id     = aws_instance.source.primary_network_interface_id
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.web_only.id
  traffic_mirror_target_id = aws_ec2_traffic_mirror_target.appliance.id
  session_number           = 1
  virtual_network_id       = var.vni
  packet_length            = var.packet_length

  tags = {
    Name = "${var.project_name}-session"
  }
}
