variable "aws_region" {
  description = "AWS Region where your AWS Organizations IAM Identity Center instance and internal ALB reside."
  type        = string
  default     = "us-west-2"
}

variable "prefix" {
  description = "Short prefix for naming Verified Access resources."
  type        = string
  default     = "ava-lab"
}

variable "policy_reference_name" {
  description = "Identifier used in Cedar policy context (e.g., idc)."
  type        = string
  default     = "idc"
}

variable "application_domain" {
  description = "Public DNS name users browse to (must match your ACM certificate CN/SAN)."
  type        = string
}

variable "domain_certificate_arn" {
  description = "ACM public TLS certificate ARN matching application_domain."
  type        = string
}

variable "endpoint_domain_prefix" {
  description = "Custom prefix prepended to the Verified Access generated endpoint DNS name."
  type        = string
  default     = "my-ava-app"
}

variable "internal_alb_arn" {
  description = "ARN of your existing internal Application Load Balancer in the same VPC."
  type        = string
}

variable "alb_protocol" {
  description = "Protocol used by the internal ALB listener: https or http."
  type        = string
  default     = "https"
}

variable "alb_port" {
  description = "Port used by the internal ALB listener (e.g., 443 or 80)."
  type        = number
  default     = 443
}

variable "subnet_ids" {
  description = "Subnets associated with your internal ALB (specify at most one subnet per Availability Zone)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group ID(s) attached to the Verified Access endpoint."
  type        = list(string)
}

variable "allowed_idc_group_id" {
  description = "IAM Identity Center Group ID permitted by the Cedar group policy."
  type        = string
}

variable "enable_allow_policy" {
  description = "Set false first to verify default-deny; set true to attach the Cedar permit policy."
  type        = bool
  default     = false
}
