terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Required by AWS WAF for global CloudFront protection packs (web ACLs) and their log groups
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
