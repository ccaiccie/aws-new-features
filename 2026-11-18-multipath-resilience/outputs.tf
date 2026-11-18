output "region_a" {
  value = var.region_a
}

output "region_b" {
  value = var.region_b
}

output "vpc_peering_connection_id" {
  description = "Pass to scripts/multipath.sh pcx ..."
  value       = aws_vpc_peering_connection.ab.id
}

output "tgw_peering_attachment_id" {
  description = "Pass to scripts/multipath.sh tgw ... (null unless enable_tgw_peering = true)"
  value       = var.enable_tgw_peering ? aws_ec2_transit_gateway_peering_attachment.ab[0].id : null
}

output "remote_route_target" {
  value = local.use_tgw_routes ? "transit gateway" : "VPC peering connection"
}

output "subnet_ids_a" {
  value = aws_subnet.a[*].id
}

output "subnet_ids_b" {
  value = aws_subnet.b[*].id
}

output "check_status_pcx" {
  description = "Command to check MultipathResilienceStatus on the VPC peering connection."
  value       = "aws ec2 describe-vpc-peering-connections --region ${var.region_a} --vpc-peering-connection-ids ${aws_vpc_peering_connection.ab.id} --query 'VpcPeeringConnections[0].[Status.Code,MultipathResilienceStatus]'"
}
