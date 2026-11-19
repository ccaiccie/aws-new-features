# Optional: prerequisites for context sharing and for the Network Manager topology view.
# The context store itself (create-context-store / associate-context-store) is not in
# hashicorp/aws 6.73.0; see README.

resource "aws_networkmanager_global_network" "this" {
  count       = var.enable_network_manager ? 1 : 0
  description = "${var.name} global network"
}

resource "aws_networkmanager_transit_gateway_registration" "this" {
  count               = var.enable_network_manager ? 1 : 0
  global_network_id   = aws_networkmanager_global_network.this[0].id
  transit_gateway_arn = aws_ec2_transit_gateway.this.arn
}
