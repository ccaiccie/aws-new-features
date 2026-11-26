variable "aws_region" {
  description = "AWS Region where the dual-stack VPC lab will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource Name tags."
  type        = string
  default     = "nt-ipv6-dns64-lab"
}

variable "vpc_ipv4_cidr" {
  description = "Primary IPv4 CIDR block for the dual-stack VPC."
  type        = string
  default     = "10.64.0.0/16"
}

variable "public_subnet_ipv4_cidr" {
  description = "IPv4 CIDR block for the public subnet hosting the NAT Gateway."
  type        = string
  default     = "10.64.1.0/24"
}

variable "availability_zone_index" {
  description = "Index into available Availability Zones in the selected region."
  type        = number
  default     = 0
}

variable "create_test_instance" {
  description = "Set true to launch a Nitro EC2 test instance in the private IPv6-only subnet with SSM Session Manager access (no inbound ports)."
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "Nitro-based EC2 instance type supporting IPv6-only subnets."
  type        = string
  default     = "t3.micro"
}
