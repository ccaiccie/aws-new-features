terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "azure_location" {
  description = "Azure Region paired with the AWS Interconnect Region (eastus, germanywestcentral, or australiaeast)."
  type        = string
  default     = "eastus"
}

variable "name_prefix" {
  description = "Prefix for optional Azure lab resources."
  type        = string
  default     = "aws-ic-azure-lab"
}

variable "azure_vnet_cidr" {
  description = "Non-overlapping Azure VNet CIDR (must not overlap with AWS VPC 10.10.0.0/16)."
  type        = string
  default     = "10.20.0.0/16"
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.azure_location
}

resource "azurerm_virtual_network" "lab" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.azure_vnet_cidr]
}

resource "azurerm_subnet" "workload" {
  name                 = "workload-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.20.255.0/27"]
}

output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "vnet_id" {
  value = azurerm_virtual_network.lab.id
}
