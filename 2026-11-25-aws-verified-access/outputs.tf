output "verified_access_instance_id" {
  value = aws_verifiedaccess_instance.main.id
}

output "verified_access_group_id" {
  value = aws_verifiedaccess_group.app_group.id
}

output "verified_access_endpoint_id" {
  value = aws_verifiedaccess_endpoint.alb_app.id
}

output "endpoint_domain" {
  description = "Create a public DNS CNAME mapping application_domain -> endpoint_domain."
  value       = aws_verifiedaccess_endpoint.alb_app.endpoint_domain
}

output "verify_cli_commands" {
  value = <<-EOT
    aws ec2 describe-verified-access-instances --verified-access-instance-ids ${aws_verifiedaccess_instance.main.id}
    aws ec2 describe-verified-access-groups --verified-access-group-ids ${aws_verifiedaccess_group.app_group.id}
    aws ec2 describe-verified-access-endpoints --verified-access-endpoint-ids ${aws_verifiedaccess_endpoint.alb_app.id}
  EOT
}
