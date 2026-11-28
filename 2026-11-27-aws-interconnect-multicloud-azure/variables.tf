variable "aws_region" {
  description = "AWS Region for the local AWS Interconnect - multicloud with Microsoft Azure (GA Regions: us-east-1, eu-central-1, ap-southeast-2)."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "eu-central-1", "ap-southeast-2"], var.aws_region)
    error_message = "AWS Interconnect - multicloud with Microsoft Azure is generally available in us-east-1, eu-central-1, and ap-southeast-2."
  }
}

variable "name_prefix" {
  description = "Prefix applied to AWS lab resource names."
  type        = string
  default     = "aws-ic-azure-lab"
}

variable "aws_vpc_cidr" {
  description = "Non-overlapping IPv4 CIDR block for the AWS VPC (must not overlap with your Azure VNet CIDR)."
  type        = string
  default     = "10.10.0.0/16"
}

variable "aws_subnet_cidr" {
  description = "Private subnet CIDR block inside the AWS VPC."
  type        = string
  default     = "10.10.1.0/24"
}

variable "azure_vnet_cidr" {
  description = "Remote Azure VNet CIDR block (documented here to enforce non-overlapping CIDR planning)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "tgw_amazon_side_asn" {
  description = "Private BGP ASN for the AWS Transit Gateway (64512-65534)."
  type        = number
  default     = 64512
}

variable "dxgw_amazon_side_asn" {
  description = "Private BGP ASN for the Direct Connect gateway (must differ from tgw_amazon_side_asn)."
  type        = number
  default     = 64513
}

variable "enable_interconnect_cli_instructions" {
  description = "EXPLICIT OPT-IN ONLY. Keep false by default. Creating an AWS Interconnect, Direct Connect gateway attachments, Transit Gateway attachments, and Azure resources incurs ongoing hourly charges until deleted."
  type        = bool
  default     = false
}

variable "interconnect_connection_id" {
  description = "Optional AWS Interconnect connection ID (mcc-xxxxxxxx) created via AWS CLI or Console. When non-empty, Terraform creates the CloudWatch utilization alarm."
  type        = string
  default     = ""
}

variable "utilization_alarm_threshold_percent" {
  description = "CloudWatch alarm threshold (%) for ConnectionUtilizationEgress."
  type        = number
  default     = 80
}

variable "interconnect_metric_dimension_name" {
  description = "CloudWatch dimension name for AWS/Interconnect utilization metrics (verify in CloudWatch once the connection emits metrics)."
  type        = string
  default     = "ConnectionId"
}
