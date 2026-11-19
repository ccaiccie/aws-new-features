variable "region" {
  description = "Region for the lab. Must be a Region where both Transit Gateway and Gateway Load Balancer are available and the feature is offered (not me-south-1 Bahrain or me-central-1 UAE)."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "tgw-gwlb"
}

variable "azs" {
  description = "Two Availability Zone names. In us-east-1, avoid the AZ whose ID is use1-az3: the network function attachment does not support it."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) == 2
    error_message = "Use exactly two Availability Zones."
  }
}

variable "spoke_a_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "spoke_b_cidr" {
  type    = string
  default = "10.2.0.0/16"
}

variable "security_vpc_cidr" {
  description = "VPC for the Gateway Load Balancer and the appliances. It has NO transit gateway attachment in this design."
  type        = string
  default     = "10.100.0.0/16"
}

variable "inspected_supernet" {
  description = "Static route in the spoke route table that sends traffic to the network function attachment."
  type        = string
  default     = "10.0.0.0/8"
}

variable "appliance_ami_id" {
  description = "AMI of a GENEVE-capable firewall appliance (vendor AMI or your own). Leave empty to skip the instances; the attachment needs healthy targets before you create it."
  type        = string
  default     = ""
}

variable "appliance_instance_type" {
  type    = string
  default = "c5.large"
}

variable "health_check_port" {
  description = "TCP port the appliance answers on for Gateway Load Balancer health checks."
  type        = number
  default     = 80
}

variable "acceptance_required" {
  description = "If true, each endpoint connection the transit gateway creates (one per AZ) stays pendingAcceptance until you accept it on the endpoint service."
  type        = bool
  default     = true
}

variable "nf_attachment_id" {
  description = "Phase 2: the tgw-attach-... ID of the network function attachment you created with the AWS CLI (scripts/nf-attachment.sh). Empty = phase 1 only."
  type        = string
  default     = ""
}

variable "enable_network_manager" {
  description = "Create a Network Manager global network and register the transit gateway (prerequisites for context sharing and for the topology view)."
  type        = bool
  default     = false
}
