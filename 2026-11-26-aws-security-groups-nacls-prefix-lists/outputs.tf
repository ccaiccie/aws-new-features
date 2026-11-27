output "vpc_id" {
  description = "Lab VPC ID"
  value       = aws_vpc.lab.id
}

output "prefix_list_id" {
  description = "Customer-managed prefix list ID"
  value       = aws_ec2_managed_prefix_list.trusted_admin.id
}

output "web_security_group_id" {
  description = "Web tier Security Group ID"
  value       = aws_security_group.web.id
}

output "app_security_group_id" {
  description = "App tier Security Group ID"
  value       = aws_security_group.app.id
}

output "public_nacl_id" {
  description = "Public subnet Network ACL ID"
  value       = aws_network_acl.public_web.id
}

output "private_nacl_id" {
  description = "Private subnet Network ACL ID"
  value       = aws_network_acl.private_app.id
}

output "web_public_ip" {
  description = "Public IPv4 address of the web tier t3.micro instance"
  value       = aws_instance.web.public_ip
}

output "app_private_ip" {
  description = "Private IPv4 address of the app tier t3.micro instance"
  value       = aws_instance.app.private_ip
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group name for VPC Flow Logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : ""
}
