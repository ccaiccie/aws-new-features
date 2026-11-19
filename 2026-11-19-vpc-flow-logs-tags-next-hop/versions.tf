terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.73.0" # tag_field_specification on aws_flow_log needs 6.56.0 or later
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      lab = var.name
    }
  }
}
