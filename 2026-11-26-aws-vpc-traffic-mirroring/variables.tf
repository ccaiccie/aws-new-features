variable "aws_region" {
  description = "AWS Region for the disposable VPC Traffic Mirroring lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for tags and resource names."
  type        = string
  default     = "tm-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the disposable lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the lab subnet."
  type        = string
  default     = "10.42.1.0/24"
}

variable "instance_type" {
  description = "Supported EC2 instance type for Traffic Mirroring source and target (T3 is on the official supported list)."
  type        = string
  default     = "t3.micro"
}

variable "admin_cidr" {
  description = "Your operator IPv4 CIDR (e.g. 203.0.113.10/32) allowed to reach the lab instances for SSH/HTTP testing."
  type        = string
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access (leave null if using AWS Systems Manager Session Manager)."
  type        = string
  default     = null
}

variable "vni" {
  description = "VXLAN Network Identifier (VNI) assigned to the traffic mirror session."
  type        = number
  default     = 100
}

variable "packet_length" {
  description = "Optional number of bytes after the VXLAN header to mirror (null mirrors the full packet; minimum 35 bytes for IPv4)."
  type        = number
  default     = null
}
