output "service_network_id" {
  description = "ID of the VPC Lattice service network."
  value       = aws_vpclattice_service_network.main.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network."
  value       = aws_vpclattice_service_network.main.arn
}

output "orders_service_id" {
  description = "ID of the orders VPC Lattice service."
  value       = aws_vpclattice_service.orders.id
}

output "orders_service_dns" {
  description = "Auto-generated VPC Lattice DNS entry for the orders service."
  value       = aws_vpclattice_service.orders.dns_entry
}

output "access_log_group_name" {
  description = "CloudWatch Log Group receiving VPC Lattice service network access logs."
  value       = aws_cloudwatch_log_group.lattice_access.name
}
