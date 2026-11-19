output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  value = aws_ec2_transit_gateway.this.arn
}

output "endpoint_service_id" {
  value = aws_vpc_endpoint_service.gwlb.id
}

output "endpoint_service_name" {
  value = aws_vpc_endpoint_service.gwlb.service_name
}

output "appliance_az_ids" {
  description = "AZ IDs of the appliance subnets; pass these to the attachment."
  value       = aws_subnet.appliance[*].availability_zone_id
}

output "route_tables" {
  value = {
    spokes     = aws_ec2_transit_gateway_route_table.spokes.id
    inspection = aws_ec2_transit_gateway_route_table.inspection.id
  }
}

output "global_network_id" {
  value = var.enable_network_manager ? aws_networkmanager_global_network.this[0].id : null
}

output "next_step" {
  value = var.nf_attachment_id == "" ? "Run scripts/nf-attachment.sh create, then set nf_attachment_id and apply again." : "Attachment ${var.nf_attachment_id} is associated with the inspection table and targeted by ${var.inspected_supernet} in the spokes table."
}
