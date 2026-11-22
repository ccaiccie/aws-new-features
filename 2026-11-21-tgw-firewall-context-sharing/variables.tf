variable "aws_region" {
  description = "AWS Region to deploy the Transit Gateway and Network Firewall lab (must be a supported Region for TGW context sharing)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for naming AWS resources in this lab."
  type        = string
  default     = "tgw-context-lab"
}

variable "dev_vpc_cidr" {
  description = "CIDR block for the Development VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "prod_vpc_cidr" {
  description = "CIDR block for the Production VPC."
  type        = string
  default     = "10.20.0.0/16"
}
