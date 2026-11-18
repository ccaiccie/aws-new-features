variable "region" {
  description = "Region for the lab. GuardDuty, Macie and Security Hub CSPM are Regional; repeat per Region in real life."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for named resources."
  type        = string
  default     = "msg-lab"
}

variable "finding_publishing_frequency" {
  description = "How often GuardDuty and Macie publish updates to existing findings: FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.finding_publishing_frequency)
    error_message = "Use FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  }
}

variable "guardduty_min_severity" {
  description = "Lowest GuardDuty numeric severity sent to the Lambda function by the native GuardDuty Finding rule (1-10; 4 = Medium, 7 = High)."
  type        = number
  default     = 4
}

variable "create_macie_job" {
  description = "Create a ONE_TIME Macie sensitive data discovery job against the lab bucket (billed by data analyzed; not covered by the Macie free trial)."
  type        = bool
  default     = true
}

variable "enable_macie_product_subscription" {
  description = "Create aws_securityhub_product_subscription for Macie. The integration is enabled automatically when both services are on, so this can conflict; default off."
  type        = bool
  default     = false
}

variable "isolation_vpc_id" {
  description = "Optional VPC ID. When set, the lab creates an isolation security group (no rules) in it and the Lambda function may move instances in that VPC into it."
  type        = string
  default     = ""
}

variable "enable_isolation" {
  description = "Let the Lambda function replace an instance's security groups with the isolation group for GuardDuty EC2 findings at or above isolation_min_severity. Default false = log only."
  type        = bool
  default     = false
}

variable "isolation_min_severity" {
  description = "GuardDuty numeric severity at or above which isolation is attempted (only when enable_isolation is true)."
  type        = number
  default     = 7
}

variable "delegated_admin_account_id" {
  description = "Optional. Only when running from an Organizations management account: designate this account as delegated admin for GuardDuty, Macie and Security Hub CSPM in this Region."
  type        = string
  default     = ""
}
