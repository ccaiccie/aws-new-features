terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.73.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az = data.aws_availability_zones.available.names[0]
}

# ---------------------------------------------------------------------------
# Three small VPCs, each with an internet gateway and a default route, so each
# one WOULD be publicly reachable if Block Public Access were not in the way.
#   app      : no exclusion      -> follows the account-level BPA mode
#   edge     : subnet exclusion  -> bidirectional internet allowed on one subnet
#   outbound : VPC exclusion     -> egress-only (outbound allowed, inbound blocked)
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  for_each             = var.vpcs
  cidr_block           = each.value.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-${each.key}" }
}

resource "aws_internet_gateway" "this" {
  for_each = var.vpcs
  vpc_id   = aws_vpc.this[each.key].id

  tags = { Name = "${var.name_prefix}-${each.key}-igw" }
}

resource "aws_subnet" "public" {
  for_each                = var.vpcs
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = each.value.subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-${each.key}-public" }
}

resource "aws_route_table" "public" {
  for_each = var.vpcs
  vpc_id   = aws_vpc.this[each.key].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[each.key].id
  }

  tags = { Name = "${var.name_prefix}-${each.key}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each       = var.vpcs
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[each.key].id
}

# ---------------------------------------------------------------------------
# Exclusions. They can exist before account-level BPA is turned on, so nothing
# is disrupted when you flip the switch. An exclusion on a VPC covers all of its
# subnets. At most 50 exclusions per account by default.
# ---------------------------------------------------------------------------
resource "aws_vpc_block_public_access_exclusion" "edge_subnet" {
  subnet_id                       = aws_subnet.public["edge"].id
  internet_gateway_exclusion_mode = "allow-bidirectional"

  tags = { Name = "${var.name_prefix}-edge-subnet-exclusion" }
}

resource "aws_vpc_block_public_access_exclusion" "outbound_vpc" {
  vpc_id                          = aws_vpc.this["outbound"].id
  internet_gateway_exclusion_mode = "allow-egress"

  tags = { Name = "${var.name_prefix}-outbound-vpc-exclusion" }
}

# ---------------------------------------------------------------------------
# ACCOUNT-LEVEL, REGION-WIDE SWITCH. Off by default in this lab.
# When enabled it affects EVERY VPC in this Region of this account, not only the
# three above. Read the README before setting enable_account_bpa = true.
# ---------------------------------------------------------------------------
resource "aws_vpc_block_public_access_options" "this" {
  count                       = var.enable_account_bpa ? 1 : 0
  internet_gateway_block_mode = var.account_bpa_mode

  depends_on = [
    aws_vpc_block_public_access_exclusion.edge_subnet,
    aws_vpc_block_public_access_exclusion.outbound_vpc,
  ]
}
