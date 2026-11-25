locals {
  firewall_tgw_attachment_id = aws_networkfirewall_firewall.this.firewall_status[0].transit_gateway_attachment_sync_states[0].attachment_id

  spokes = {
    dev = {
      vpc_id           = aws_vpc.dev.id
      tgw_attachment   = aws_ec2_transit_gateway_vpc_attachment.dev.id
      cidr             = aws_vpc.dev.cidr_block
      destination_cidr = aws_vpc.prod.cidr_block
    }
    prod = {
      vpc_id           = aws_vpc.prod.id
      tgw_attachment   = aws_ec2_transit_gateway_vpc_attachment.prod.id
      cidr             = aws_vpc.prod.cidr_block
      destination_cidr = aws_vpc.dev.cidr_block
    }
  }

  spoke_subnets = {
    dev-a  = { spoke = "dev", id = aws_subnet.dev_private_a.id }
    dev-b  = { spoke = "dev", id = aws_subnet.dev_private_b.id }
    prod-a = { spoke = "prod", id = aws_subnet.prod_web_a.id }
    prod-b = { spoke = "prod", id = aws_subnet.prod_db_b.id }
  }
}

resource "aws_route_table" "spoke" {
  for_each = local.spokes
  vpc_id   = each.value.vpc_id
  tags     = merge(local.common_tags, { Name = "${var.project_name}-${each.key}" })
}

resource "aws_route_table_association" "spoke" {
  for_each       = local.spoke_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.spoke[each.value.spoke].id
}

resource "aws_route" "peer_via_tgw" {
  for_each               = local.spokes
  route_table_id         = aws_route_table.spoke[each.key].id
  destination_cidr_block = each.value.destination_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  # A gateway ID alone doesn't guarantee the VPC's attachment is available yet.
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dev, aws_ec2_transit_gateway_vpc_attachment.prod]
}

resource "aws_ec2_transit_gateway_route_table" "before_inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(local.common_tags, { Name = "${var.project_name}-before-inspection" })
}

resource "aws_ec2_transit_gateway_route_table" "after_inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(local.common_tags, { Name = "${var.project_name}-after-inspection" })
}

# TGW selects the route table by ingress attachment, not the destination VPC.
resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each                       = local.spokes
  transit_gateway_attachment_id  = each.value.tgw_attachment
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.before_inspection.id
}

resource "aws_ec2_transit_gateway_route_table_association" "firewall" {
  transit_gateway_attachment_id  = local.firewall_tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.after_inspection.id
}

resource "aws_ec2_transit_gateway_route" "inspect" {
  for_each                       = local.spokes
  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = local.firewall_tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.before_inspection.id
}

resource "aws_ec2_transit_gateway_route" "deliver" {
  for_each                       = local.spokes
  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = each.value.tgw_attachment
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.after_inspection.id
}
