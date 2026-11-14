terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.73.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_route53profiles_profile" "primary" {
  name = "${var.name_prefix}-primary"
}

resource "aws_route53profiles_profile" "secondary" {
  name = "${var.name_prefix}-secondary"
}

# Private hosted zones must be created with at least one VPC. These zones are
# associated to the profiles so the profile carries the DNS configuration
# described in the lesson.
resource "aws_route53_zone" "primary" {
  name = var.primary_zone_name

  vpc {
    vpc_id = aws_vpc.lab.id
  }
}

resource "aws_route53_zone" "secondary" {
  name = var.secondary_zone_name

  vpc {
    vpc_id = aws_vpc.lab.id
  }
}

resource "aws_route53profiles_resource_association" "primary_zone" {
  name         = "${var.name_prefix}-primary-zone"
  profile_id   = aws_route53profiles_profile.primary.id
  resource_arn = aws_route53_zone.primary.arn
}

resource "aws_route53profiles_resource_association" "secondary_zone" {
  name         = "${var.name_prefix}-secondary-zone"
  profile_id   = aws_route53profiles_profile.secondary.id
  resource_arn = aws_route53_zone.secondary.arn
}

# Provider 6.73.0 does not have a priority argument. AWS requires a unique
# priority (100-9900) when two profiles are associated to the same VPC, so
# this lab associates only the primary profile. Use the CLI in the README
# to associate the secondary profile with --priority.
resource "aws_route53profiles_association" "primary" {
  name        = "${var.name_prefix}-primary-assoc"
  profile_id  = aws_route53profiles_profile.primary.id
  resource_id = aws_vpc.lab.id
}
