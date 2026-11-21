variable "region" {
  description = "Region for the lab. Automated internet firewall is in public preview in all AWS commercial Regions (not GovCloud or China)."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource. NSM names allow letters, numbers, spaces and _ . : / = + - @."
  type        = string
  default     = "aif-lab"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the lab VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "policy_mode" {
  description = "Enforcement mode of the internet firewall policy: MONITOR (log only, recommended first) or ENFORCE (block matching traffic)."
  type        = string
  default     = "MONITOR"

  validation {
    condition     = contains(["MONITOR", "ENFORCE"], var.policy_mode)
    error_message = "policy_mode must be MONITOR or ENFORCE."
  }
}

variable "default_subnet_connectivity" {
  description = "Default subnet connectivity type of the policy: flexible (recommended), bidirectional or outbound-only."
  type        = string
  default     = "flexible"

  validation {
    condition     = contains(["flexible", "bidirectional", "outbound-only"], var.default_subnet_connectivity)
    error_message = "default_subnet_connectivity must be flexible, bidirectional or outbound-only."
  }
}

variable "policy_priority" {
  description = "NSM policy priority (lower number = higher priority). Must be unused by any other policy in this account and Region."
  type        = number
  default     = 900
}

variable "managed_ips_rule_group_arns" {
  description = "Optional ARNs of IPS-engine rule groups (for example AWS managed threat signature groups) to add, one NSM inspection rule each. Empty = mode rule only."
  type        = list(string)
  default     = []
}

variable "multi_account" {
  description = "Set true only when this account is the NSM administrator of an organization; adds AccountFilter IncludeAll to the VPC scope. Leave false for single-account mode."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "Instance type for the two test instances. Avoid EC2 Mac and the ML types unsupported in preview."
  type        = string
  default     = "t3.micro"
}

variable "test_client_cidr" {
  description = "Optional CIDR (for example your public IP /32) allowed to reach the public instance on TCP 8080, to test filtered inbound traffic. Empty = no inbound rule."
  type        = string
  default     = ""
}
