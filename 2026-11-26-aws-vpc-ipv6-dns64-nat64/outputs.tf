output "vpc_id" {
  description = "ID of the dual-stack VPC."
  value       = aws_vpc.main.id
}

output "vpc_ipv6_cidr_block" {
  description = "Amazon-provided /56 IPv6 GUA CIDR block assigned to the VPC."
  value       = aws_vpc.main.ipv6_cidr_block
}

output "private_ipv6_subnet_id" {
  description = "ID of the private IPv6-only subnet with DNS64 enabled."
  value       = aws_subnet.private_ipv6_only.id
}

output "private_ipv6_subnet_cidr" {
  description = "IPv6 /64 CIDR block of the private IPv6-only subnet."
  value       = aws_subnet.private_ipv6_only.ipv6_cidr_block
}

output "egress_only_igw_id" {
  description = "ID of the Egress-Only Internet Gateway."
  value       = aws_egress_only_internet_gateway.eigw.id
}

output "nat_gateway_id" {
  description = "ID of the public NAT Gateway performing NAT64."
  value       = aws_nat_gateway.nat.id
}

output "private_route_table_id" {
  description = "ID of the private IPv6 route table."
  value       = aws_route_table.private_ipv6.id
}

output "test_instance_id" {
  description = "ID of the optional IPv6-only EC2 test instance (if created)."
  value       = var.create_test_instance ? aws_instance.ipv6_test[0].id : null
}
