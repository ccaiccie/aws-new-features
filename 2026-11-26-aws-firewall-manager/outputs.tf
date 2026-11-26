output "primary_security_group_id" {
  description = "Primary security group ID in the Firewall Manager administrator account."
  value       = var.create_example_common_sg_policy ? aws_security_group.primary_https_baseline[0].id : null
}

output "common_sg_policy_id" {
  description = "AWS Firewall Manager Common Security Group policy ID."
  value       = var.create_example_common_sg_policy ? aws_fms_policy.common_sg_policy[0].id : null
}

output "alb_wafv2_policy_id" {
  description = "AWS Firewall Manager WAFv2 policy ID."
  value       = var.create_example_waf_policy ? aws_fms_policy.alb_wafv2_policy[0].id : null
}
