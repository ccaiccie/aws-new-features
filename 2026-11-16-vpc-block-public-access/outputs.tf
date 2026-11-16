output "vpc_ids" {
  description = "Lab VPC IDs by name."
  value       = { for k, v in aws_vpc.this : k => v.id }
}

output "exclusion_ids" {
  description = "Exclusion IDs."
  value = {
    edge_subnet  = aws_vpc_block_public_access_exclusion.edge_subnet.id
    outbound_vpc = aws_vpc_block_public_access_exclusion.outbound_vpc.id
  }
}

output "account_bpa_mode" {
  description = "Account-level mode managed by this lab, or off when not enabled."
  value       = var.enable_account_bpa ? var.account_bpa_mode : "not managed (off)"
}
