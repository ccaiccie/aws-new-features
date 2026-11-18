variable "region" {
  type        = string
  description = "IPAM home Region and the Region of the lab VPC."
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names and tags."
  default     = "ipam-lab"
}

variable "ipam_tier" {
  type        = string
  description = "IPAM tier. Private IPv4 pools need the Advanced tier (billed per active IP per hour)."
  default     = "advanced"

  validation {
    condition     = contains(["free", "advanced"], var.ipam_tier)
    error_message = "Use free or advanced."
  }
}

variable "top_level_cidr" {
  type        = string
  description = "Whole internal block for the top-level pool (no locale)."
  default     = "10.0.0.0/8"
}

variable "regional_netmask" {
  type        = number
  description = "Size of the block the top-level pool hands to the Regional pool."
  default     = 12
}

variable "vpc_netmask" {
  type        = number
  description = "Size the lab VPC asks the Regional pool for (must sit between the pool min and max)."
  default     = 20
}

variable "environment_tag" {
  type        = string
  description = "Value of the env tag the Regional pool requires on VPCs that allocate from it."
  default     = "prod"
}

variable "prefix_list_max_entries" {
  type        = number
  description = "Max entries of the managed prefix list. IPAM never resizes it, so leave headroom."
  default     = 20
}
