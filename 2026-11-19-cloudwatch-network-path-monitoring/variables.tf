variable "region" {
  description = "Region for the lab. Must be one of the 17 Regions where Performance Monitor is available (for example us-east-1, us-east-2, us-west-2, eu-west-1)."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for named resources."
  type        = string
  default     = "npm-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.98.0.0/16"
}

variable "instance_type" {
  description = "Instance type for the client and server (Amazon Linux 2023, x86_64)."
  type        = string
  default     = "t3.micro"
}

variable "performance_monitor_id" {
  description = "MonitorId of the performance monitor you create with scripts/create-performance-monitor.sh or the console (hashicorp/aws 6.73.0 has no resource for it). Leave empty on the first apply; set it and apply again to create the alarm and dashboard."
  type        = string
  default     = ""
}

variable "impact_alarm_threshold" {
  description = "ImpactScore threshold for the any-path alarm. ImpactScore is fixed per level: 0 None, 25 Low, 65 Medium, 95 High."
  type        = number
  default     = 95

  validation {
    condition     = contains([25, 65, 95], var.impact_alarm_threshold)
    error_message = "Use 25 (Low), 65 (Medium) or 95 (High)."
  }
}

variable "alarm_email" {
  description = "Optional email address subscribed to the alarm SNS topic (you must confirm the subscription email)."
  type        = string
  default     = ""
}

variable "onprem_probe_destination" {
  description = "Optional on-premises IP address reachable from the lab VPC (for example over Direct Connect or Site-to-Site VPN). When set, the lab creates a Network Synthetic Monitor monitor with an ICMP probe from the client subnet. The lab itself does not build hybrid connectivity."
  type        = string
  default     = ""
}
