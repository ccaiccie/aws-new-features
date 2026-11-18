locals {
  tags           = { Project = var.name_prefix, Lab = "multipath-resilience" }
  use_tgw_routes = var.enable_tgw_peering && var.route_via == "tgw"
}

data "aws_caller_identity" "current" {
  provider = aws.a
}

data "aws_availability_zones" "a" {
  provider = aws.a
  state    = "available"
}

data "aws_availability_zones" "b" {
  provider = aws.b
  state    = "available"
}

# ---------------- Region A (requester) ----------------
resource "aws_vpc" "a" {
  provider             = aws.a
  cidr_block           = var.vpc_a_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${var.name_prefix}-vpc-a" })
}

resource "aws_subnet" "a" {
  provider          = aws.a
  count             = 2
  vpc_id            = aws_vpc.a.id
  cidr_block        = cidrsubnet(var.vpc_a_cidr, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.a.names[count.index]
  tags              = merge(local.tags, { Name = "${var.name_prefix}-a-private-${count.index + 1}" })
}

resource "aws_route_table" "a" {
  provider = aws.a
  vpc_id   = aws_vpc.a.id
  tags     = merge(local.tags, { Name = "${var.name_prefix}-a-rt" })
}

resource "aws_route_table_association" "a" {
  provider       = aws.a
  count          = 2
  subnet_id      = aws_subnet.a[count.index].id
  route_table_id = aws_route_table.a.id
}

resource "aws_security_group" "a" {
  provider    = aws.a
  name        = "${var.name_prefix}-a-sg"
  description = "Allow ICMP and TCP 5060 (SIP-like test traffic) from the peer VPC"
  vpc_id      = aws_vpc.a.id
  tags        = merge(local.tags, { Name = "${var.name_prefix}-a-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "a_icmp" {
  provider          = aws.a
  security_group_id = aws_security_group.a.id
  cidr_ipv4         = var.vpc_b_cidr
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
}

resource "aws_vpc_security_group_ingress_rule" "a_tcp" {
  provider          = aws.a
  security_group_id = aws_security_group.a.id
  cidr_ipv4         = var.vpc_b_cidr
  ip_protocol       = "tcp"
  from_port         = 5060
  to_port           = 5060
}

resource "aws_vpc_security_group_egress_rule" "a_all" {
  provider          = aws.a
  security_group_id = aws_security_group.a.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------- Region B (accepter) ----------------
resource "aws_vpc" "b" {
  provider             = aws.b
  cidr_block           = var.vpc_b_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${var.name_prefix}-vpc-b" })
}

resource "aws_subnet" "b" {
  provider          = aws.b
  count             = 2
  vpc_id            = aws_vpc.b.id
  cidr_block        = cidrsubnet(var.vpc_b_cidr, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.b.names[count.index]
  tags              = merge(local.tags, { Name = "${var.name_prefix}-b-private-${count.index + 1}" })
}

resource "aws_route_table" "b" {
  provider = aws.b
  vpc_id   = aws_vpc.b.id
  tags     = merge(local.tags, { Name = "${var.name_prefix}-b-rt" })
}

resource "aws_route_table_association" "b" {
  provider       = aws.b
  count          = 2
  subnet_id      = aws_subnet.b[count.index].id
  route_table_id = aws_route_table.b.id
}

resource "aws_security_group" "b" {
  provider    = aws.b
  name        = "${var.name_prefix}-b-sg"
  description = "Allow ICMP and TCP 5060 (SIP-like test traffic) from the peer VPC"
  vpc_id      = aws_vpc.b.id
  tags        = merge(local.tags, { Name = "${var.name_prefix}-b-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "b_icmp" {
  provider          = aws.b
  security_group_id = aws_security_group.b.id
  cidr_ipv4         = var.vpc_a_cidr
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
}

resource "aws_vpc_security_group_ingress_rule" "b_tcp" {
  provider          = aws.b
  security_group_id = aws_security_group.b.id
  cidr_ipv4         = var.vpc_a_cidr
  ip_protocol       = "tcp"
  from_port         = 5060
  to_port           = 5060
}

resource "aws_vpc_security_group_egress_rule" "b_all" {
  provider          = aws.b
  security_group_id = aws_security_group.b.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------- Cross-Region VPC peering ----------------
# Multipath Resilience is a peering connection option (AllowMultipathResilience) that hashicorp/aws 6.73.0
# does not expose yet. Terraform builds the connection; scripts/multipath.sh turns the option on for both sides.
resource "aws_vpc_peering_connection" "ab" {
  provider      = aws.a
  vpc_id        = aws_vpc.a.id
  peer_vpc_id   = aws_vpc.b.id
  peer_region   = var.region_b
  peer_owner_id = data.aws_caller_identity.current.account_id
  auto_accept   = false # cross-Region: accepted below in Region B
  tags          = merge(local.tags, { Name = "${var.name_prefix}-pcx", Side = "requester" })
}

resource "aws_vpc_peering_connection_accepter" "ab" {
  provider                  = aws.b
  vpc_peering_connection_id = aws_vpc_peering_connection.ab.id
  auto_accept               = true
  tags                      = merge(local.tags, { Name = "${var.name_prefix}-pcx", Side = "accepter" })
}

resource "aws_route" "a_to_b_pcx" {
  provider                  = aws.a
  count                     = local.use_tgw_routes ? 0 : 1
  route_table_id            = aws_route_table.a.id
  destination_cidr_block    = var.vpc_b_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.ab.id
  depends_on                = [aws_vpc_peering_connection_accepter.ab]
}

resource "aws_route" "b_to_a_pcx" {
  provider                  = aws.b
  count                     = local.use_tgw_routes ? 0 : 1
  route_table_id            = aws_route_table.b.id
  destination_cidr_block    = var.vpc_a_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.ab.id
  depends_on                = [aws_vpc_peering_connection_accepter.ab]
}
