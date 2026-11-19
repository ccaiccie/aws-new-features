variable "region" {
  description = "Region for the lab. VPC Flow Logs tag and next-hop fields (version 11) must be available in it, for example us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "flowlogs-v11"
}

variable "vpc_cidr" {
  description = "CIDR block of the lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "instance_type" {
  description = "Instance type for the two test instances."
  type        = string
  default     = "t3.micro"
}

variable "aggregation_interval" {
  description = "Maximum aggregation interval in seconds: 60 or 600. Nitro instances always aggregate in 60 seconds or less."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 600], var.aggregation_interval)
    error_message = "aggregation_interval must be 60 or 600."
  }
}

variable "log_retention_days" {
  description = "Retention of the CloudWatch Logs log group."
  type        = number
  default     = 3
}

variable "enable_s3_parquet" {
  description = "Also publish the same records to S3 as Parquet with Hive-compatible, per-hour partitions (for Athena)."
  type        = bool
  default     = false
}
