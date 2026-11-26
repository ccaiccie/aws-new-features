variable "aws_region" {
  description = "AWS Region for the Client VPN endpoint, VPC, and Lambda connect handler."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix for lab resources."
  type        = string
  default     = "posture-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.60.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the associated private subnet."
  type        = string
  default     = "10.60.1.0/24"
}

variable "client_cidr_block" {
  description = "Client VPN IPv4 CIDR block (/22 to /12, must not overlap VPC CIDR)."
  type        = string
  default     = "10.61.0.0/22"
}

variable "server_certificate_arn" {
  description = "ARN of the ACM server certificate in aws_region."
  type        = string
}

variable "client_root_certificate_arn" {
  description = "ARN of the ACM client root CA certificate for mutual authentication."
  type        = string
}

variable "allowed_platforms" {
  description = "Comma-separated OS platforms allowed by the sample connect handler Lambda."
  type        = string
  default     = "mac,win,linux"
}
