data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  az = data.aws_availability_zones.available.names[var.availability_zone_index]
}

# 1. Dual-stack VPC with an Amazon-provided /56 IPv6 GUA CIDR block
resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_ipv4_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# 2. Internet Gateway (for the public subnet and NAT Gateway egress)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# 3. Egress-Only Internet Gateway (stateful IPv6-only outbound internet access)
resource "aws_egress_only_internet_gateway" "eigw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-eigw"
  }
}

# 4. Public Subnet (IPv4 + IPv6 dual-stack) hosting the NAT Gateway
# Note: AWS docs note the NAT Gateway subnet does not need to be dual-stack for NAT64,
# but must be a public subnet with 0.0.0.0/0 -> Internet Gateway.
resource "aws_subnet" "public" {
  vpc_id                          = aws_vpc.main.id
  availability_zone               = local.az
  cidr_block                      = var.public_subnet_ipv4_cidr
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0)
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# 5. Elastic IP and Public NAT Gateway (NAT64 is automatically available)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.project_name}-natgw"
  }

  depends_on = [aws_internet_gateway.igw]
}

# 6. Public Route Table (0.0.0.0/0 -> IGW, ::/0 -> IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rtb"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 7. Private IPv6-Only Subnet with DNS64 enabled
resource "aws_subnet" "private_ipv6_only" {
  vpc_id                                         = aws_vpc.main.id
  availability_zone                              = local.az
  ipv6_native                                    = true
  ipv6_cidr_block                                = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation                = true
  enable_dns64                                   = true
  enable_resource_name_dns_aaaa_record_on_launch = true
  private_dns_hostname_type_on_launch            = "resource-name"

  tags = {
    Name = "${var.project_name}-private-ipv6-subnet"
  }
}

# 8. Private Route Table:
#    - 64:ff9b::/96 -> NAT Gateway (NAT64 for IPv4 destinations)
#    - ::/0         -> Egress-Only Internet Gateway (outbound IPv6 internet)
resource "aws_route_table" "private_ipv6" {
  vpc_id = aws_vpc.main.id

  route {
    ipv6_cidr_block = "64:ff9b::/96"
    nat_gateway_id  = aws_nat_gateway.nat.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.eigw.id
  }

  tags = {
    Name = "${var.project_name}-private-ipv6-rtb"
  }
}

resource "aws_route_table_association" "private_ipv6" {
  subnet_id      = aws_subnet.private_ipv6_only.id
  route_table_id = aws_route_table.private_ipv6.id
}

# 9. Security Group for the IPv6-only test instance (no inbound rules; IPv6 egress allowed)
resource "aws_security_group" "ipv6_test" {
  count       = var.create_test_instance ? 1 : 0
  name        = "${var.project_name}-ipv6-test-sg"
  description = "Allows outbound IPv6 (including 64:ff9b::/96 for NAT64); no inbound access."
  vpc_id      = aws_vpc.main.id

  egress {
    description      = "Outbound IPv6 including synthesized 64:ff9b::/96 NAT64 traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}-ipv6-test-sg"
  }
}

# 10. Minimal IAM Role for AWS Systems Manager Session Manager (no SSH port needed)
resource "aws_iam_role" "ssm_role" {
  count = var.create_test_instance ? 1 : 0
  name  = "${var.project_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = var.create_test_instance ? 1 : 0
  role       = aws_iam_role.ssm_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  count = var.create_test_instance ? 1 : 0
  name  = "${var.project_name}-ssm-profile"
  role  = aws_iam_role.ssm_role[0].name
}

# 11. Optional Nitro EC2 Test Instance in the Private IPv6-Only Subnet
resource "aws_instance" "ipv6_test" {
  count                  = var.create_test_instance ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_ipv6_only.id
  vpc_security_group_ids = [aws_security_group.ipv6_test[0].id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile[0].name

  tags = {
    Name = "${var.project_name}-ipv6-test-vm"
  }
}
