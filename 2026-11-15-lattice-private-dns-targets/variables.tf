variable "region" {
  type        = string
  description = "AWS Region for every lab resource. VPC Lattice must be available there."
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
  default     = "lattice-pdns"
}

variable "producer_cidr" {
  type        = string
  description = "CIDR of the producer VPC (owns the target and the resource gateway)."
  default     = "10.0.0.0/16"
}

variable "consumer_cidr" {
  type        = string
  description = "CIDR of the consumer VPC. It may even overlap the producer; nothing is routed between them."
  default     = "10.1.0.0/16"
}

variable "private_zone_name" {
  type        = string
  description = "Private hosted zone that only the producer VPC can resolve."
  default     = "svc.internal"
}

variable "service_label" {
  type        = string
  description = "Host label of the shared service; the FQDN becomes <label>.<zone>."
  default     = "payments"
}

variable "service_port" {
  type        = number
  description = "TCP port the target listens on and the resource configuration shares."
  default     = 8443
}

variable "dns_resolution" {
  type        = string
  description = "Resource gateway DNS resolution: IN_VPC (private names) or PUBLIC (public resolvers). Immutable."
  default     = "IN_VPC"

  validation {
    condition     = contains(["IN_VPC", "PUBLIC"], var.dns_resolution)
    error_message = "dns_resolution must be IN_VPC or PUBLIC."
  }
}

variable "private_dns_preference" {
  type        = string
  description = "Consumer private DNS preference on the service network VPC association."
  default     = "SPECIFIED_DOMAINS_ONLY"

  validation {
    condition     = contains(["VERIFIED_DOMAINS_ONLY", "ALL_DOMAINS", "VERIFIED_DOMAINS_AND_SPECIFIED_DOMAINS", "SPECIFIED_DOMAINS_ONLY"], var.private_dns_preference)
    error_message = "Use VERIFIED_DOMAINS_ONLY, ALL_DOMAINS, VERIFIED_DOMAINS_AND_SPECIFIED_DOMAINS or SPECIFIED_DOMAINS_ONLY."
  }
}

variable "create_instances" {
  type        = bool
  description = "Create a small target web server in the producer VPC and a test client in the consumer VPC."
  default     = true
}

variable "target_ip" {
  type        = string
  description = "Address for the private A record when create_instances is false (an existing target in the producer VPC)."
  default     = "10.0.1.50"
}

variable "instance_type" {
  type        = string
  description = "Instance type for the optional test instances."
  default     = "t3.micro"
}
