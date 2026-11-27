variable "aws_region" {
  description = "AWS Region for the two-tier VPC packet-filter lab."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the lab VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR block for the public web tier subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  description = "IPv4 CIDR block for the private app tier subnet."
  type        = string
  default     = "10.20.2.0/24"
}

variable "trusted_admin_cidrs" {
  description = "List of trusted IPv4 CIDR blocks (e.g., your public /32 IP) stored in the customer-managed prefix list."
  type = list(object({
    cidr        = string
    description = string
  }))
}

variable "prefix_list_max_entries" {
  description = "Maximum entries for the customer-managed prefix list. Note: this value counts toward the 60-rule Security Group quota."
  type        = number
  default     = 5
}

variable "instance_type" {
  description = "EC2 instance type for the lab instances (lowest-cost Nitro example: t3.micro)."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Optional existing EC2 key pair name for SSH access to the web instance. Leave empty to skip key pair."
  type        = string
  default     = ""
}

variable "block_test_cidr" {
  description = "Optional /32 CIDR to explicitly DENY in the public Network ACL (rule 90) to prove stateless NACL deny behavior."
  type        = string
  default     = ""
}

variable "enable_ephemeral_outbound_nacl" {
  description = "Set to false temporarily to demonstrate how a stateless Network ACL breaks return traffic when outbound ephemeral ports (1024-65535) are missing."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch Logs (1-day retention) to observe ACCEPT and REJECT records."
  type        = bool
  default     = true
}
