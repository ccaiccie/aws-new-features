output "ipam_id" {
  description = "IPAM ID."
  value       = aws_vpc_ipam.this.id
}

output "regional_pool_id" {
  description = "Regional pool ID (use it in VPC modules instead of a typed CIDR)."
  value       = aws_vpc_ipam_pool.regional.id
}

output "regional_pool_cidr" {
  description = "Block the top-level pool allocated to the Regional pool."
  value       = aws_vpc_ipam_pool_cidr.regional.cidr
}

output "previewed_next_cidr" {
  description = "The next free block the Regional pool would hand out at plan time."
  value       = aws_vpc_ipam_preview_next_cidr.next.cidr
}

output "vpc_cidr" {
  description = "CIDR IPAM allocated to the lab VPC."
  value       = aws_vpc.app.cidr_block
}

output "prefix_list_id" {
  description = "Managed prefix list referenced by the security group."
  value       = aws_ec2_managed_prefix_list.internal.id
}
