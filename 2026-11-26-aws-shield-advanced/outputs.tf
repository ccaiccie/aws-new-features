output "route53_health_check_id" {
  description = "ID of the safe Route 53 HTTPS health check."
  value       = aws_route53_health_check.app_health.id
}

output "ddos_alerts_sns_topic_arn" {
  description = "ARN of the SNS topic for DDoS CloudWatch alarm notifications."
  value       = aws_sns_topic.ddos_alerts.arn
}

output "ddos_detected_alarm_arn" {
  description = "ARN of the CloudWatch DDoSDetected metric alarm."
  value       = aws_cloudwatch_metric_alarm.ddos_detected.arn
}
