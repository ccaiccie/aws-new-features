variable "aws_region" {
  description = "AWS Region to deploy the shared NAT gateway lab (must be an FCA-supported Region)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for naming and tagging lab resources."
  type        = string
  default     = "vpc-fca-lab"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the lab VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR block for the public subnet hosting the shared NAT gateway."
  type        = string
  default     = "10.20.0.0/24"
}

variable "team_alpha_subnet_cidr" {
  description = "IPv4 CIDR block for Team Alpha's private subnet."
  type        = string
  default     = "10.20.10.0/24"
}

variable "team_beta_subnet_cidr" {
  description = "IPv4 CIDR block for Team Beta's private subnet."
  type        = string
  default     = "10.20.20.0/24"
}

variable "availability_zone" {
  description = "Optional Availability Zone override. Leave empty to use the first available AZ in the Region."
  type        = string
  default     = ""
}
