variable "region_a" {
  type        = string
  description = "Requester Region (Region A)."
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2", "eu-west-1"], var.region_a)
    error_message = "Multipath Resilience launched in us-east-1, us-east-2, us-west-1, us-west-2 and eu-west-1."
  }
}

variable "region_b" {
  type        = string
  description = "Accepter Region (Region B). Must differ from region_a: the feature is for cross-Region traffic."
  default     = "us-west-2"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2", "eu-west-1"], var.region_b)
    error_message = "Multipath Resilience launched in us-east-1, us-east-2, us-west-1, us-west-2 and eu-west-1."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names and tags."
  default     = "mpr-lab"
}

variable "vpc_a_cidr" {
  type        = string
  description = "CIDR of the VPC in Region A."
  default     = "10.10.0.0/16"
}

variable "vpc_b_cidr" {
  type        = string
  description = "CIDR of the VPC in Region B (must not overlap vpc_a_cidr)."
  default     = "10.20.0.0/16"
}

variable "enable_tgw_peering" {
  type        = bool
  description = "Also build a transit gateway in each Region, attach the VPCs and create an inter-Region TGW peering attachment."
  default     = false
}

variable "route_via" {
  type        = string
  description = "Which connection the VPC route tables use for the remote VPC CIDR: peering (VPC peering) or tgw (needs enable_tgw_peering = true)."
  default     = "peering"

  validation {
    condition     = contains(["peering", "tgw"], var.route_via)
    error_message = "Use peering or tgw."
  }
}
