# Phase 2. hashicorp/aws 6.73.0 has no resource for a transit gateway network function
# attachment of type Gateway Load Balancer, so the attachment itself is created with the
# AWS CLI (scripts/nf-attachment.sh). Paste its tgw-attach-... ID into nf_attachment_id
# and apply again: Terraform then associates it and adds the static route.
# Both resources below are standard and accept any transit gateway attachment ID.

locals {
  nf = var.nf_attachment_id == "" ? 0 : 1
}

resource "aws_ec2_transit_gateway_route_table_association" "nf" {
  count                          = local.nf
  transit_gateway_attachment_id  = var.nf_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Only static routes can target a network function attachment.
resource "aws_ec2_transit_gateway_route" "to_inspection" {
  count                          = local.nf
  destination_cidr_block         = var.inspected_supernet
  transit_gateway_attachment_id  = var.nf_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}
