variable "aws_region" {
  description = "AWS Region for the public ALB and its regional AWS WAF web ACL."
  type        = string
  default     = "us-west-2"
}

variable "prefix" {
  description = "Short prefix for lab resource names."
  type        = string
  default     = "waf-lab"
}

variable "custom_rule_count_mode" {
  description = "When true, the custom x-lab-block rule runs in Count mode (test/tune). Set false to Block (403)."
  type        = bool
  default     = false
}

variable "rate_limit_5min" {
  description = "Rate-based rule threshold (requests per 5-minute window per IP, minimum 100)."
  type        = number
  default     = 300
}

variable "example_blocked_cidrs" {
  description = "Example RFC 5737 documentation CIDRs for the lab IP set (never commit real production lists)."
  type        = list(string)
  default     = ["203.0.113.0/24"]
}
