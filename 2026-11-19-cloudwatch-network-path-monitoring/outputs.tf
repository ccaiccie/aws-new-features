output "vpc_id" {
  value = aws_vpc.lab.id
}

output "vpc_arn" {
  description = "Pass this to create-performance-monitor as an AWS::EC2::VPC target."
  value       = aws_vpc.lab.arn
}

output "client_az" {
  value = aws_subnet.client.availability_zone
}

output "server_az" {
  value = aws_subnet.server.availability_zone
}

output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "sns_topic_arn" {
  value = aws_sns_topic.network_health.arn
}

output "create_monitor_command" {
  description = "Documented CLI call to create the performance monitor (no Terraform resource exists in hashicorp/aws 6.73.0)."
  value       = "aws networkflowmonitor create-performance-monitor --region ${var.region} --monitor-name ${var.name_prefix}-paths --targets '[{\"type\":\"AWS::EC2::VPC\",\"identifier\":\"${aws_vpc.lab.arn}\"}]'"
}

output "any_path_alarm_query" {
  description = "Metrics Insights query used by the any-path alarm (empty until performance_monitor_id is set)."
  value       = local.have_monitor ? local.any_path_query : ""
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
