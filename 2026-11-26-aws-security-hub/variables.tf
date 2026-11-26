variable "aws_region" {
  description = "Single AWS Region for the Security Hub CSPM practice lab."
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix applied to lab resource names."
  type        = string
  default     = "sechub-lab"
}

variable "enable_fsbp_standard" {
  description = "Enable the AWS Foundational Security Best Practices (FSBP) v1.0.0 standard."
  type        = bool
  default     = true
}

variable "enable_automation_rule" {
  description = "Create a safe Security Hub CSPM automation rule that tags INFORMATIONAL findings with a note."
  type        = bool
  default     = true
}

variable "enable_custom_action_pipeline" {
  description = "Create a Security Hub custom action, EventBridge rule, and read-only triage Lambda."
  type        = bool
  default     = true
}
