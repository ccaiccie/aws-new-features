variable "aws_region" {
  description = "AWS Region for the CloudWatch alarm and SNS topic (Shield metrics publish to us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short prefix for naming the safe supporting lab resources."
  type        = string
  default     = "shield-adv-lab"
}

variable "health_check_fqdn" {
  description = "Public HTTPS FQDN to probe with the Route 53 health check (must return HTTP 200 to report healthy)."
  type        = string
  default     = "example.com"
}

variable "health_check_path" {
  description = "HTTPS path for the Route 53 health check."
  type        = string
  default     = "/"
}

variable "monitored_resource_arn_placeholder" {
  description = "Placeholder ARN for the CloudWatch DDoSDetected alarm dimension (does NOT subscribe to Shield Advanced)."
  type        = string
  default     = "arn:aws:cloudfront::123456789012:distribution/EXAMPLEDISTID"
}
