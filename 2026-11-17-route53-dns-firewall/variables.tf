variable "region" {
  type        = string
  description = "Region for the lab. DNS Firewall is regional."
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
  default     = "dnsfw-lab"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of the lab VPC."
  default     = "10.60.0.0/16"
}

variable "blocked_domains" {
  type        = list(string)
  description = "Custom block list. Each entry may start with *, otherwise letters, digits and hyphens."
  default     = ["blocked.example.com.", "*.bad-example.net."]
}

variable "allowed_domains" {
  type        = list(string)
  description = "Exceptions evaluated first (priority 100)."
  default     = ["partner.example.org."]
}

variable "override_cname" {
  type        = string
  description = "CNAME returned for names on the custom block list (OVERRIDE block response)."
  default     = "sinkhole.example.com."
}

variable "managed_aggregate_list_id" {
  type        = string
  description = "ID of AWSManagedDomainsAggregateThreatList in this Region (see README). Leave empty to skip rule 200."
  default     = ""
}

variable "tunneling_action" {
  type        = string
  description = "Action for the DNS Firewall Advanced tunneling rule: ALERT or BLOCK."
  default     = "ALERT"

  validation {
    condition     = contains(["ALERT", "BLOCK"], var.tunneling_action)
    error_message = "Advanced rules support only ALERT or BLOCK."
  }
}

variable "tunneling_confidence" {
  type        = string
  description = "Confidence threshold for the tunneling rule: HIGH, MEDIUM or LOW."
  default     = "MEDIUM"

  validation {
    condition     = contains(["HIGH", "MEDIUM", "LOW"], var.tunneling_confidence)
    error_message = "Use HIGH, MEDIUM or LOW."
  }
}

variable "firewall_fail_open" {
  type        = string
  description = "VPC DNS Firewall fail mode. DISABLED = fail closed (default behaviour), ENABLED = fail open."
  default     = "DISABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.firewall_fail_open)
    error_message = "Use ENABLED or DISABLED."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Retention of the Resolver query log group."
  default     = 7
}
