# Optional: inter-Region Transit Gateway peering (enable_tgw_peering = true).
# Multipath Resilience can be allowed on the TGW peering attachment with scripts/multipath.sh (both sides).

resource "aws_ec2_transit_gateway" "a" {
  provider                        = aws.a
  count                           = var.enable_tgw_peering ? 1 : 0
  description                     = "${var.name_prefix} TGW A"
  amazon_side_asn                 = 64512
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags                            = merge(local.tags, { Name = "${var.name_prefix}-tgw-a" })
}

resource "aws_ec2_transit_gateway" "b" {
  provider                        = aws.b
  count                           = var.enable_tgw_peering ? 1 : 0
  description                     = "${var.name_prefix} TGW B"
  amazon_side_asn                 = 64513
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags                            = merge(local.tags, { Name = "${var.name_prefix}-tgw-b" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "a" {
  provider           = aws.a
  count              = var.enable_tgw_peering ? 1 : 0
  transit_gateway_id = aws_ec2_transit_gateway.a[0].id
  vpc_id             = aws_vpc.a.id
  subnet_ids         = aws_subnet.a[*].id
  tags               = merge(local.tags, { Name = "${var.name_prefix}-tgw-a-vpc" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "b" {
  provider           = aws.b
  count              = var.enable_tgw_peering ? 1 : 0
  transit_gateway_id = aws_ec2_transit_gateway.b[0].id
  vpc_id             = aws_vpc.b.id
  subnet_ids         = aws_subnet.b[*].id
  tags               = merge(local.tags, { Name = "${var.name_prefix}-tgw-b-vpc" })
}

resource "aws_ec2_transit_gateway_peering_attachment" "ab" {
  provider                = aws.a
  count                   = var.enable_tgw_peering ? 1 : 0
  transit_gateway_id      = aws_ec2_transit_gateway.a[0].id
  peer_transit_gateway_id = aws_ec2_transit_gateway.b[0].id
  peer_region             = var.region_b
  peer_account_id         = data.aws_caller_identity.current.account_id
  tags                    = merge(local.tags, { Name = "${var.name_prefix}-tgw-peering", Side = "requester" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "ab" {
  provider                      = aws.b
  count                         = var.enable_tgw_peering ? 1 : 0
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.ab[0].id
  tags                          = merge(local.tags, { Name = "${var.name_prefix}-tgw-peering", Side = "accepter" })
}

# Peering attachments do not propagate routes: add static routes in each default TGW route table.
resource "aws_ec2_transit_gateway_route" "a_to_b" {
  provider                       = aws.a
  count                          = var.enable_tgw_peering ? 1 : 0
  destination_cidr_block         = var.vpc_b_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.ab[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.a[0].association_default_route_table_id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.ab]
}

resource "aws_ec2_transit_gateway_route" "b_to_a" {
  provider                       = aws.b
  count                          = var.enable_tgw_peering ? 1 : 0
  destination_cidr_block         = var.vpc_a_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.ab[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.b[0].association_default_route_table_id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.ab]
}

# VPC routes point at the transit gateway ID (not the attachment) when route_via = "tgw".
resource "aws_route" "a_to_b_tgw" {
  provider               = aws.a
  count                  = local.use_tgw_routes ? 1 : 0
  route_table_id         = aws_route_table.a.id
  destination_cidr_block = var.vpc_b_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.a[0].id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.a]
}

resource "aws_route" "b_to_a_tgw" {
  provider               = aws.b
  count                  = local.use_tgw_routes ? 1 : 0
  route_table_id         = aws_route_table.b.id
  destination_cidr_block = var.vpc_a_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.b[0].id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.b]
}
