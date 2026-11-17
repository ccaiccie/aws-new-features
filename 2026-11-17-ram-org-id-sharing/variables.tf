variable "region" {
  type        = string
  description = "Region for the lab. AWS RAM shares are Regional."
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
  default     = "ram-org-lab"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of the network-account VPC whose subnets are shared."
  default     = "10.70.0.0/16"
}

variable "enable_org_sharing" {
  type        = bool
  description = "Turn on RAM sharing with AWS Organizations (creates the RAM service-linked role). Only works in the management account; leave false if it is already on or you are in a member account."
  default     = false
}

variable "org_share_principal" {
  type        = string
  description = "Principal for the org-scoped share: an organization ARN or an OU ARN. Empty = the ARN of the organization this account belongs to."
  default     = ""
}

variable "retain_share_account_ids" {
  type        = list(string)
  description = "12-digit account IDs for the migration share (retain sharing on account leave organization). Empty = skip the migration share."
  default     = []

  validation {
    condition     = alltrue([for a in var.retain_share_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "Each entry must be a 12-digit AWS account ID. OUs and organizations are not allowed in a retain share."
  }
}

variable "create_transit_gateway" {
  type        = bool
  description = "Create a transit gateway and put it in the migration share."
  default     = true
}

variable "onprem_prefixes" {
  type        = list(string)
  description = "Example on-premises CIDRs for the customer-managed prefix list."
  default     = ["192.168.10.0/24", "192.168.20.0/24"]
}
