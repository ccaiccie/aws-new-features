output "azure_automation_assume_role_arn" {
  description = "ARN of the Automation assume role created for Microsoft Azure Cloud Connector executions."
  value       = aws_iam_role.azure_automation_assume.arn
}

output "gcp_automation_assume_role_arn" {
  description = "ARN of the Automation assume role created for Google Cloud Connector executions."
  value       = aws_iam_role.gcp_automation_assume.arn
}

output "runbook_names" {
  description = "Names of the Systems Manager Automation runbooks created by this lab."
  value = {
    azure_assert_vm_running = aws_ssm_document.azure_assert_vm_running.name
    gcp_start_and_wait_vm   = aws_ssm_document.gcp_start_and_wait_vm.name
    azure_sdk_inspect_vm    = aws_ssm_document.azure_sdk_inspect_vm.name
  }
}

output "next_step_cli_hint" {
  description = "Run aws ssm start-automation-execution in the same AWS Region as your Cloud Connector."
  value       = "aws ssm start-automation-execution --region ${var.aws_region} --cli-input-json file://examples/start-azure.json"
}
