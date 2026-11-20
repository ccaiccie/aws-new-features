output "health_check_source_id" {
  description = "Route 53 health check source ID (from the CloudFormation stack)."
  value       = aws_cloudformation_stack.private_health_checks.outputs["HealthCheckSourceId"]
}

output "primary_health_check_id" {
  value = aws_cloudformation_stack.private_health_checks.outputs["PrimaryCheckId"]
}

output "secondary_health_check_id" {
  value = aws_cloudformation_stack.private_health_checks.outputs["SecondaryCheckId"]
}

output "record" {
  description = "Failover record to resolve from inside the VPC."
  value       = local.app_fqdn
}

output "primary_ip" {
  value = local.primary
}

output "secondary_ip" {
  value = local.standby
}

output "primary_instance_id" {
  value = aws_instance.web[0].id
}

output "test_client_instance_id" {
  value = var.enable_test_client ? aws_instance.client[0].id : null
}

output "alarm_name" {
  description = "CloudWatch alarm in the source Region."
  value       = aws_cloudwatch_metric_alarm.primary_unhealthy.alarm_name
}
