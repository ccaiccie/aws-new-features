variable "region" {
  description = "Region for the VPC, the health check source and the alarm. Private endpoint health checks run from (and report metrics in) this Region. Pick a Region with at least three AZs (not us-west-1)."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "r53-private-hc"
}

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR of the lab VPC. Must be a private (RFC 1918) range: domain-name checks need a private primary IPv4 CIDR."
  type        = string
  default     = "10.20.0.0/16"
}

variable "app_port" {
  description = "TCP port the two web servers listen on."
  type        = number
  default     = 8080
}

variable "health_path" {
  description = "HTTP path the private health checks request. Must return 2xx or 3xx when healthy."
  type        = string
  default     = "/health"
}

variable "request_interval" {
  description = "Seconds between checks: 30 (standard) or 10 (fast; extra charge)."
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.request_interval)
    error_message = "request_interval must be 10 or 30."
  }
}

variable "failure_threshold" {
  description = "Consecutive failures (or successes) before the status flips. Default 3."
  type        = number
  default     = 3

  validation {
    condition     = var.failure_threshold >= 1 && var.failure_threshold <= 10
    error_message = "failure_threshold must be between 1 and 10."
  }
}

variable "zone_name" {
  description = "Private hosted zone name."
  type        = string
  default     = "lab.internal"
}

variable "record_name" {
  description = "Record (relative to zone_name) that fails over between the primary and the secondary."
  type        = string
  default     = "app"
}

variable "instance_type" {
  description = "Instance type for the web servers and the test client."
  type        = string
  default     = "t3.micro"
}

variable "enable_test_client" {
  description = "Create a test client instance plus SSM interface endpoints so you can resolve the record from inside the VPC with Session Manager (no internet access needed)."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Optional email address subscribed to the SNS topic (you must confirm the subscription). Leave empty to skip."
  type        = string
  default     = ""
}
