variable "region" {
  type        = string
  description = "AWS region for the VPC and Route 53 Profiles."
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
  default     = "r53prof-lab"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the lab VPC."
  default     = "10.90.0.0/16"
}

variable "primary_zone_name" {
  type        = string
  description = "DNS name of the private hosted zone attached to the primary profile."
  default     = "app.example.internal"
}

variable "secondary_zone_name" {
  type        = string
  description = "DNS name of the private hosted zone attached to the secondary profile."
  default     = "shared.example.internal"
}
