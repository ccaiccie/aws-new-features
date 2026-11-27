output "global_network_id" {
  description = "ID of the Cloud WAN Global Network"
  value       = aws_networkmanager_global_network.main.id
}

output "core_network_id" {
  description = "ID of the Cloud WAN Core Network"
  value       = aws_networkmanager_core_network.main.id
}

output "core_network_arn" {
  description = "ARN of the Cloud WAN Core Network"
  value       = aws_networkmanager_core_network.main.arn
}

output "prod_attachment_id" {
  description = "ID of the prod VPC attachment"
  value       = aws_networkmanager_vpc_attachment.prod.id
}

output "shared_attachment_id" {
  description = "ID of the shared VPC attachment"
  value       = aws_networkmanager_vpc_attachment.shared.id
}

output "rendered_policy_json" {
  description = "Rendered Cloud WAN core network policy JSON"
  value       = data.aws_networkmanager_core_network_policy_document.main.json
}
