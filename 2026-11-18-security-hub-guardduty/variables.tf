variable "region" {
  description = "Region for the lab. GuardDuty and Security Hub CSPM are Regional; repeat the lab per Region in real life."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for named resources."
  type        = string
  default     = "shgd-lab"
}

variable "finding_publishing_frequency" {
  description = "How often GuardDuty publishes updates to existing findings: FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  type        = string
  default     = "FIFTEEN_MINUTES"
}

variable "enable_protection_features" {
  description = "GuardDuty protection plans to turn on (aws_guardduty_detector_feature names). Leave RUNTIME_MONITORING out unless you want the agent and its cost."
  type        = list(string)
  default     = ["S3_DATA_EVENTS", "EBS_MALWARE_PROTECTION", "LAMBDA_NETWORK_LOGS"]
}

variable "enable_runtime_monitoring" {
  description = "Turn on GuardDuty Runtime Monitoring with automated agent management for EC2 (extra cost)."
  type        = bool
  default     = false
}

variable "trusted_scanner_ip" {
  description = "Public IPv4 address of your own vulnerability scanner. Port probes from it are auto-archived by a GuardDuty suppression rule."
  type        = string
  default     = "192.0.2.10"
}

variable "threat_list_ips" {
  description = "Custom threat list entries (documentation ranges by default). Matches produce *.Custom findings."
  type        = list(string)
  default     = ["198.51.100.7", "203.0.113.0/24"]
}

variable "enable_cis_standard" {
  description = "Subscribe Security Hub CSPM to CIS AWS Foundations Benchmark v5.0.0 in addition to FSBP."
  type        = bool
  default     = true
}

variable "enable_guardduty_product_subscription" {
  description = "Create aws_securityhub_product_subscription for GuardDuty. The integration is enabled automatically, so this can fail with a conflict; default off."
  type        = bool
  default     = false
}

variable "enable_security_hub_v2" {
  description = "Also enable the unified AWS Security Hub (OCSF) with aws_securityhub_account_v2. Check Security Hub pricing first."
  type        = bool
  default     = false
}

variable "enable_network_scanning" {
  description = "Turn on the Security Hub NETWORK_SCANNING feature (requires enable_security_hub_v2)."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Optional email for the SNS topic. Leave empty to skip the subscription."
  type        = string
  default     = ""
}

variable "delegated_admin_account_id" {
  description = "Optional. Only when running from an Organizations management account: designate this account as GuardDuty and Security Hub delegated admin."
  type        = string
  default     = ""
}
