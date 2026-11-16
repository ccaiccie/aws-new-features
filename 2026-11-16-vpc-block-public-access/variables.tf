variable "region" {
  description = "AWS Region. Block Public Access is configured per Region."
  type        = string
  default     = "us-east-2"
}

variable "name_prefix" {
  description = "Prefix for Name tags."
  type        = string
  default     = "bpa-lab"
}

variable "vpcs" {
  description = "The three lab VPCs and their address plans."
  type = map(object({
    cidr        = string
    subnet_cidr = string
  }))
  default = {
    app      = { cidr = "10.90.0.0/16", subnet_cidr = "10.90.1.0/24" }
    edge     = { cidr = "10.91.0.0/16", subnet_cidr = "10.91.1.0/24" }
    outbound = { cidr = "10.92.0.0/16", subnet_cidr = "10.92.1.0/24" }
  }
}

variable "enable_account_bpa" {
  description = "Turn on account-level, Region-wide VPC Block Public Access. Affects every VPC in the Region. Default false."
  type        = bool
  default     = false
}

variable "account_bpa_mode" {
  description = "block-bidirectional or block-ingress (used only when enable_account_bpa is true)."
  type        = string
  default     = "block-ingress"

  validation {
    condition     = contains(["block-bidirectional", "block-ingress"], var.account_bpa_mode)
    error_message = "account_bpa_mode must be block-bidirectional or block-ingress."
  }
}
