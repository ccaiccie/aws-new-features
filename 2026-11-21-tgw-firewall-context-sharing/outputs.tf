output "dev_vpc_id" {
  description = "Development VPC ID (use as a context identifier in context-aware rules)"
  value       = aws_vpc.dev.id
}

output "prod_vpc_id" {
  description = "Production VPC ID (use as a context identifier in context-aware rules)"
  value       = aws_vpc.prod.id
}

output "prod_web_sg_id" {
  description = "Production Web Tier Security Group ID"
  value       = aws_security_group.prod_web.id
}

output "prod_db_sg_id" {
  description = "Production Database Tier Security Group ID"
  value       = aws_security_group.prod_db.id
}

output "transit_gateway_id" {
  description = "AWS Transit Gateway ID"
  value       = aws_ec2_transit_gateway.this.id
}

output "dev_tgw_attachment_id" {
  description = "Development VPC Transit Gateway Attachment ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.dev.id
}

output "prod_tgw_attachment_id" {
  description = "Production VPC Transit Gateway Attachment ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.prod.id
}

output "network_firewall_arn" {
  description = "Transit Gateway-attached AWS Network Firewall ARN"
  value       = aws_networkfirewall_firewall.this.arn
}

output "global_network_id" {
  description = "AWS Network Manager Global Network ID"
  value       = aws_networkmanager_global_network.this.id
}
