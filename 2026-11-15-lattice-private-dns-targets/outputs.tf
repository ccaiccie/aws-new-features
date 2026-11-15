output "service_fqdn" {
  description = "Private name consumers dial; it resolves only through VPC Lattice in the consumer VPC."
  value       = local.fqdn
}

output "resource_gateway_id" {
  value = aws_vpclattice_resource_gateway.this.id
}

output "resource_configuration_id" {
  value = aws_vpclattice_resource_configuration.service.id
}

output "service_network_id" {
  value = aws_vpclattice_service_network.this.id
}

output "service_network_resource_association_dns" {
  description = "DNS entry VPC Lattice generated for the resource association."
  value       = aws_vpclattice_service_network_resource_association.service.dns_entry
}

output "consumer_vpc_id" {
  value = aws_vpc.consumer.id
}

output "client_instance_id" {
  description = "Use with aws ec2 get-console-output to see the LATTICE-TEST lines."
  value       = var.create_instances ? aws_instance.client[0].id : null
}
