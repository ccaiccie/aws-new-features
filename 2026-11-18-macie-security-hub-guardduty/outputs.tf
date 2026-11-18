output "detector_id" {
  description = "GuardDuty detector ID (use with create-sample-findings)."
  value       = aws_guardduty_detector.this.id
}

output "lab_bucket" {
  description = "S3 bucket with fake test data for Macie."
  value       = aws_s3_bucket.lab_data.id
}

output "macie_job_id" {
  description = "Macie one-time job ID, if created."
  value       = try(aws_macie2_classification_job.lab[0].job_id, null)
}

output "responder_log_group" {
  description = "CloudWatch Logs group of the Lambda responder."
  value       = aws_cloudwatch_log_group.responder.name
}

output "event_rules" {
  description = "EventBridge rule names."
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.name }
}

output "isolation_security_group_id" {
  description = "Isolation security group, if isolation_vpc_id was set."
  value       = try(aws_security_group.isolation[0].id, null)
}
