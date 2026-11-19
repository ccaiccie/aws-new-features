resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name} - network function attachment lab"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  # Prerequisite: Encryption Support must be disabled, or creating a
  # network function attachment of type Gateway Load Balancer is rejected.
  encryption_support = "disable"
  tags               = { Name = var.name }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  for_each           = local.spokes
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.spoke[each.key].id
  subnet_ids         = [for k, s in local.spoke_subnets : aws_subnet.spoke[k].id if s.spoke == each.key]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "${var.name}-spoke-${each.key}" }
}

# Pre-inspection: spokes look up here and are sent to the network function attachment.
resource "aws_ec2_transit_gateway_route_table" "spokes" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "${var.name}-spokes" }
}

# Post-inspection: associated with the network function attachment; knows every spoke.
resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "${var.name}-inspection" }
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each                       = local.spokes
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

# Spoke VPC attachments propagate into the post-inspection table.
# (A network function attachment itself does not support propagation.)
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_to_inspection" {
  for_each                       = local.spokes
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}
