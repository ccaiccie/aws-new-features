output "securityhub_arn" {
  description = "ARN of the enabled Security Hub CSPM hub."
  value       = aws_securityhub_account.this.arn
}

output "fsbp_subscription_arn" {
  description = "ARN of the enabled AWS Foundational Security Best Practices subscription."
  value       = var.enable_fsbp_standard ? aws_securityhub_standards_subscription.fsbp[0].id : null
}

output "custom_action_arn" {
  description = "ARN of the Security Hub custom action target."
  value       = var.enable_custom_action_pipeline ? aws_securityhub_action_target.triage[0].arn : null
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule matching the custom action."
  value       = var.enable_custom_action_pipeline ? aws_cloudwatch_event_rule.custom_action[0].name : null
}

output "triage_lambda_name" {
  description = "Name of the read-only triage Lambda function."
  value       = var.enable_custom_action_pipeline ? aws_lambda_function.triage[0].function_name : null
}
