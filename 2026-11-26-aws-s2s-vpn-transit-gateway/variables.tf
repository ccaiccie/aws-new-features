variable "aws_region" {
  description = "AWS Region to deploy the Transit Gateway and Site-to-Site VPN lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all lab resources."
  type        = string
  default     = "tgw-s2s-vpn-lab"
}

variable "tgw_asn" {
  description = "Amazon-side private ASN for the Transit Gateway (64512-65534 or 4200000000-4294967294)."
  type        = number
  default     = 64512
}

variable "cgw_asn" {
  description = "Customer gateway BGP ASN (must differ from tgw_asn for eBGP)."
  type        = number
  default     = 65000
}

variable "customer_gateway_ip" {
  description = "Static public IPv4 address of your on-premises or disposable simulated customer gateway device."
  type        = string
  default     = "203.0.113.10"
}

variable "onprem_cidr" {
  description = "Simulated on-premises network CIDR block (non-overlapping with AWS VPC CIDRs)."
  type        = string
  default     = "192.168.100.0/24"
}

variable "static_routes_only" {
  description = "Set to false for dynamic BGP routing (recommended, supports ECMP). Set to true for static routing."
  type        = bool
  default     = false
}

variable "enable_acceleration" {
  description = "Set to true to enable AWS Global Accelerator-backed Accelerated Site-to-Site VPN (adds Global Accelerator hourly and data transfer charges; cannot be toggled after creation)."
  type        = bool
  default     = false
}

variable "tunnel1_inside_cidr" {
  description = "Inside IPv4 /30 CIDR for Tunnel 1 from 169.254.0.0/16 (excluding AWS reserved blocks)."
  type        = string
  default     = "169.254.10.0/30"
}

variable "tunnel2_inside_cidr" {
  description = "Inside IPv4 /30 CIDR for Tunnel 2 from 169.254.0.0/16 (excluding AWS reserved blocks)."
  type        = string
  default     = "169.254.20.0/30"
}
