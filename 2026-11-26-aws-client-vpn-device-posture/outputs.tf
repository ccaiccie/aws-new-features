output "client_vpn_endpoint_id" {
  description = "ID of the AWS Client VPN endpoint."
  value       = aws_ec2_client_vpn_endpoint.lab.id
}

output "client_vpn_dns_name" {
  description = "DNS name of the Client VPN endpoint."
  value       = aws_ec2_client_vpn_endpoint.lab.dns_name
}

output "connect_handler_arn" {
  description = "ARN of the AWSClientVPN- client connect handler Lambda."
  value       = aws_lambda_function.connect_handler.arn
}

output "log_group_name" {
  description = "CloudWatch Logs group receiving connection and policy evaluation logs."
  value       = aws_cloudwatch_log_group.cvpn.name
}
