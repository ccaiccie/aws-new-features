variable "aws_region" {
  description = "Primary AWS Region for the Cloud WAN core network edge and lab VPCs. Use us-east-1 if testing optional RAM sharing."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for naming lab resources."
  type        = string
  default     = "cwan-unit4-lab"
}

variable "asn_range" {
  description = "Private ASN range for Cloud WAN core network edges (64512-65534 or 4200000000-4294967294)."
  type        = string
  default     = "65000-65100"
}

variable "allow_prod_shared_sharing" {
  description = "Set to false to keep prod and shared segments isolated (blocked). Set to true to add a segment-actions share rule allowing prod and shared to exchange attachment routes."
  type        = bool
  default     = false
}

variable "enable_ram_share" {
  description = "Optional: share the core network with a second AWS account via AWS RAM. Must be run in us-east-1 per AWS documentation."
  type        = bool
  default     = false
}

variable "ram_share_account_id" {
  description = "Optional: 12-digit AWS account ID to share the core network with when enable_ram_share is true."
  type        = string
  default     = ""
}
