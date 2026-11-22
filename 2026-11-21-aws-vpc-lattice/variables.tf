variable "aws_region" {
  description = "AWS Region where the VPC Lattice lab resources are deployed."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to all lab resource names."
  type        = string
  default     = "nt-lattice-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the consumer/provider lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "subnet_cidrs" {
  description = "Private subnet CIDR blocks across two Availability Zones."
  type        = list(string)
  default     = ["10.42.1.0/24", "10.42.2.0/24"]
}

variable "allowed_org_id" {
  description = "Optional AWS Organizations ID (e.g., o-xxxxxxxxxx) to restrict the service network auth policy. Leave empty to allow the current AWS account only."
  type        = string
  default     = ""
}

variable "enable_ram_share" {
  description = "Set to true to create an AWS RAM resource share for the VPC Lattice service network."
  type        = bool
  default     = false
}

variable "ram_principal_account_ids" {
  description = "List of AWS account IDs or Organization ARNs to share the service network with when enable_ram_share is true."
  type        = list(string)
  default     = []
}
