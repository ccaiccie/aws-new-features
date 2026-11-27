variable "aws_region" {
  description = "AWS Region where the disposable VPC lab will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short prefix for naming all lab resources."
  type        = string
  default     = "vpc-analysis-lab"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the disposable lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "instance_type" {
  description = "Small EC2 instance type used for source and destination endpoints."
  type        = string
  default     = "t3.micro"
}

variable "run_reachability_analyses" {
  description = "Set to true to run aws_ec2_network_insights_analysis during terraform apply (incurs per-analysis charges)."
  type        = bool
  default     = false
}
