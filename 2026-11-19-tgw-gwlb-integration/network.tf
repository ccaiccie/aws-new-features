locals {
  spokes = {
    a = var.spoke_a_cidr
    b = var.spoke_b_cidr
  }
  # one /24 per AZ per spoke for workloads (and for the TGW VPC attachment ENIs)
  spoke_subnets = {
    for pair in setproduct(keys(local.spokes), range(length(var.azs))) :
    "${pair[0]}-${pair[1]}" => {
      spoke = pair[0]
      az    = var.azs[pair[1]]
      cidr  = cidrsubnet(local.spokes[pair[0]], 8, pair[1])
    }
  }
}

# ---------- spoke VPCs ----------
resource "aws_vpc" "spoke" {
  for_each             = local.spokes
  cidr_block           = each.value
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-spoke-${each.key}" }
}

resource "aws_subnet" "spoke" {
  for_each          = local.spoke_subnets
  vpc_id            = aws_vpc.spoke[each.value.spoke].id
  availability_zone = each.value.az
  cidr_block        = each.value.cidr
  tags              = { Name = "${var.name}-spoke-${each.key}" }
}

resource "aws_route_table" "spoke" {
  for_each = local.spokes
  vpc_id   = aws_vpc.spoke[each.key].id
  tags     = { Name = "${var.name}-spoke-${each.key}" }
}

# everything outside the VPC goes to the transit gateway
resource "aws_route" "spoke_to_tgw" {
  for_each               = local.spokes
  route_table_id         = aws_route_table.spoke[each.key].id
  destination_cidr_block = var.inspected_supernet
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

resource "aws_route_table_association" "spoke" {
  for_each       = local.spoke_subnets
  subnet_id      = aws_subnet.spoke[each.key].id
  route_table_id = aws_route_table.spoke[each.value.spoke].id
}

# ---------- security (appliance) VPC: GWLB + appliances, no TGW attachment ----------
resource "aws_vpc" "security" {
  cidr_block = var.security_vpc_cidr
  tags       = { Name = "${var.name}-security" }
}

resource "aws_subnet" "appliance" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.security.id
  availability_zone = var.azs[count.index]
  cidr_block        = cidrsubnet(var.security_vpc_cidr, 8, count.index)
  tags              = { Name = "${var.name}-appliance-${count.index}" }
}
