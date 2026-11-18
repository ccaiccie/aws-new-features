terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.73.0"
    }
  }
}

# Requester side (Region A). Both Regions must be Multipath Resilience launch Regions:
# us-east-1, us-east-2, us-west-1, us-west-2, eu-west-1.
provider "aws" {
  alias  = "a"
  region = var.region_a
}

# Accepter side (Region B).
provider "aws" {
  alias  = "b"
  region = var.region_b
}
