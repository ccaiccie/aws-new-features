output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.main.id
}

output "transit_gateway_route_table_id" {
  description = "Default Transit Gateway Route Table ID"
  value       = aws_ec2_transit_gateway.main.association_default_route_table_id
}

output "vpn_connection_id" {
  description = "Site-to-Site VPN Connection ID"
  value       = aws_vpn_connection.tgw_vpn.id
}

output "vpn_transit_gateway_attachment_id" {
  description = "Transit Gateway Attachment ID created automatically for the VPN connection"
  value       = aws_vpn_connection.tgw_vpn.transit_gateway_attachment_id
}

output "routing_mode" {
  description = "Configured routing mode (BGP dynamic or Static)"
  value       = var.static_routes_only ? "static" : "dynamic-bgp"
}

output "acceleration_enabled" {
  description = "Whether AWS Global Accelerator-backed acceleration is enabled"
  value       = aws_vpn_connection.tgw_vpn.enable_acceleration
}

output "tunnel1_outside_ip" {
  description = "AWS outside public IPv4 address for Tunnel 1"
  value       = aws_vpn_connection.tgw_vpn.tunnel1_address
}

output "tunnel1_inside_cidr" {
  description = "Inside IPv4 /30 CIDR for Tunnel 1 (AWS=.1, CGW=.2)"
  value       = aws_vpn_connection.tgw_vpn.tunnel1_inside_cidr
}

output "tunnel2_outside_ip" {
  description = "AWS outside public IPv4 address for Tunnel 2"
  value       = aws_vpn_connection.tgw_vpn.tunnel2_address
}

output "tunnel2_inside_cidr" {
  description = "Inside IPv4 /30 CIDR for Tunnel 2 (AWS=.1, CGW=.2)"
  value       = aws_vpn_connection.tgw_vpn.tunnel2_inside_cidr
}
