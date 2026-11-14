variable "region" {
  type        = string
  description = "AWS region for the lab."
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
  default     = "nfw-ngfw-lab"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the lab VPC."
  default     = "10.80.0.0/16"
}

variable "firewall_subnet_cidrs" {
  type        = list(string)
  description = "Two subnet CIDRs, in different Availability Zones, used if you create a firewall endpoint."
  default     = ["10.80.0.0/24", "10.80.1.0/24"]
}

variable "create_firewall" {
  type        = bool
  description = "Set true to also deploy a Network Firewall (hourly endpoint charge). Leave false to create only the policy and rule group."
  default     = false
}
