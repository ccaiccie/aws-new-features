variable "aws_region" {
  description = "AWS Region where the Systems Manager Cloud Connector and Automation runbooks live. Must match the connector Region."
  type        = string
  default     = "us-east-1"
}

variable "connector_name_slug" {
  description = "Short slug used in the Automation assume role name (e.g., MyConnector)."
  type        = string
  default     = "LabConnector"
}

variable "azure_cloud_connector_id" {
  description = "Existing Systems Manager Cloud Connector ID for Microsoft Azure (first 8 chars are used in the role name). Leave placeholder until connector is created."
  type        = string
  default     = "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
}

variable "azure_federation_role_arn" {
  description = "ARN of the Azure Cloud Connector IAM federation role (from aws ssm get-cloud-connector --query RoleArn). Optional: if empty, uses a scoped wildcard for the current account."
  type        = string
  default     = ""
}

variable "gcp_cloud_connector_id" {
  description = "Existing Systems Manager Cloud Connector ID for Google Cloud (first 8 chars are used in the role name). Leave placeholder until connector is created."
  type        = string
  default     = "b2c3d4e5-6789-01bc-def0-EXAMPLE22222"
}

variable "gcp_federation_role_arn" {
  description = "ARN of the Google Cloud Connector IAM federation role (from aws ssm get-cloud-connector --query RoleArn). Optional: if empty, uses a scoped wildcard for the current account."
  type        = string
  default     = ""
}

variable "azure_sdk_package" {
  description = "Systems Manager Automation SDK package identifier for Microsoft Azure actions and scripts."
  type        = string
  default     = "azure_202610"
}

variable "gcp_sdk_package" {
  description = "Systems Manager Automation SDK package identifier for Google Cloud actions and scripts."
  type        = string
  default     = "gcp_202610"
}

variable "name_prefix" {
  description = "Prefix applied to Systems Manager Automation runbooks created by this lab."
  type        = string
  default     = "NT-MulticloudLab"
}
