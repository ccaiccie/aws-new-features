# One VPC, one internet gateway, three subnets in ONE Availability Zone.
# Automated internet firewall is billed per VPC per AZ, so the lab stays in a single AZ.
# No NAT gateway and no firewall subnets: the firewall and its native NAT live at the internet gateway.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"] # automated internet firewall is not supported in Local Zones
  }
}

locals {
  az = data.aws_availability_zones.available.names[0]
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
    # The NSM VPC scope selects VPCs with this tag (see firewall.tf).
    "internet-inspection" = "enabled"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name}-igw" }
}

# Public subnet: the instance gets a public IP. With flexible connectivity it is bidirectional (filtered).
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1) # 10.40.1.0/24
  availability_zone       = local.az
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public" }
}

# Private subnet: NO public IPs, but the default route points at the internet gateway.
# With flexible connectivity its resources get outbound-only access through the firewall's native NAT.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2) # 10.40.2.0/24
  availability_zone = local.az
  tags              = { Name = "${var.name}-private" }
}

# Isolated subnet: also has a default route to the internet gateway (the "trap" case),
# but is tagged network-zone = isolated, so the policy overrides it to "exclude".
resource "aws_subnet" "isolated" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3) # 10.40.3.0/24
  availability_zone = local.az
  tags = {
    Name           = "${var.name}-isolated"
    "network-zone" = "isolated"
  }
}

# One route table for all three subnets: 0.0.0.0/0 -> igw. That is the whole routing design.
resource "aws_route_table" "to_igw" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name}-rt-igw" }
}

resource "aws_route" "default_igw" {
  route_table_id         = aws_route_table.to_igw.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.to_igw.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.to_igw.id
}

resource "aws_route_table_association" "isolated" {
  subnet_id      = aws_subnet.isolated.id
  route_table_id = aws_route_table.to_igw.id
}
