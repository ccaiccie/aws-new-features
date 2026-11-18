output "detector_id" {
  value = aws_guardduty_detector.this.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.findings.arn
}

output "event_log_group" {
  value = aws_cloudwatch_log_group.findings.name
}

output "event_rules" {
  value = { for k, r in aws_cloudwatch_event_rule.findings : k => r.name }
}

output "standards_enabled" {
  value = concat([aws_securityhub_standards_subscription.fsbp.standards_arn], [for s in aws_securityhub_standards_subscription.cis : s.standards_arn])
}

output "netops_custom_action_arn" {
  value = aws_securityhub_action_target.netops.arn
}
