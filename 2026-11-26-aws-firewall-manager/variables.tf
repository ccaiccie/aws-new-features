variable "aws_region" {
  description = "AWS Region where the Firewall Manager administrator policies will be created."
  type        = string
  default     = "us-east-1"
}

variable "policy_name_prefix" {
  description = "Prefix for Firewall Manager policies and supporting lab resources."
  type        = string
  default     = "nt-fms-lab"
}

variable "in_scope_ou_ids" {
  description = "List of AWS Organizations Organizational Unit (OU) IDs in scope for the policies (for example: [\"ou-exam-11111111\"])."
  type        = list(string)
}

variable "excluded_account_ids" {
  description = "Optional list of AWS account IDs to exclude from scope (AWS best practice: exclude the Firewall Manager administrator account for security group policies)."
  type        = list(string)
  default     = []
}

variable "exclude_tag_key" {
  description = "Resource tag key used to exempt out-of-scope resources from Firewall Manager policies."
  type        = string
  default     = "fms-exempt"
}

variable "exclude_tag_value" {
  description = "Resource tag value that matches the exemption key (exact match required by Firewall Manager)."
  type        = string
  default     = "true"
}

variable "remediation_enabled" {
  description = "Set to false (recommended first) to audit and flag noncompliant resources without modifying them. Set to true to enable automatic remediation."
  type        = bool
  default     = false
}

variable "delete_unused_fm_managed_resources" {
  description = "Automatically remove Firewall Manager-managed protections when a resource leaves policy scope."
  type        = bool
  default     = true
}

variable "delete_all_policy_resources_on_destroy" {
  description = "Clean up Firewall Manager-managed web ACLs or replica security groups when the policy is deleted."
  type        = bool
  default     = true
}

variable "admin_primary_sg_vpc_id" {
  description = "VPC ID in the Firewall Manager administrator account where the primary baseline security group will be created."
  type        = string
}

variable "create_example_waf_policy" {
  description = "Whether to create the example org-wide AWS WAFv2 policy for Application Load Balancers."
  type        = bool
  default     = true
}

variable "create_example_common_sg_policy" {
  description = "Whether to create the example org-wide Common Security Group policy."
  type        = bool
  default     = true
}
