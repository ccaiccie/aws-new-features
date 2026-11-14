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

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "firewall" {
  count             = 2
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.firewall_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.name_prefix}-firewall-${count.index}"
  }
}

resource "aws_networkfirewall_rule_group" "stateful" {
  name        = "${var.name_prefix}-stateful"
  description = "Sample stateful rules used by the Classic Network Firewall policy in this lab"
  type        = "STATEFUL"
  capacity    = 100

  rule_group {
    rules_source {
      stateful_rule {
        action = "DROP"
        header {
          destination      = "ANY"
          destination_port = "ANY"
          direction        = "ANY"
          protocol         = "IP"
          source           = "10.255.255.0/24"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["1"]
        }
      }
      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "ANY"
          direction        = "ANY"
          protocol         = "IP"
          source           = var.vpc_cidr
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["2"]
        }
      }
    }
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }
}

# Classic policy (stateless engine, then stateful engine). The NGFW policy
# type announced on November 10, 2026 is not an argument on this resource
# in AWS provider 6.73.0.
resource "aws_networkfirewall_firewall_policy" "lab" {
  name        = "${var.name_prefix}-classic-policy"
  description = "Classic Network Firewall policy for the NGFW lesson lab"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_default_actions = [
      "aws:drop_strict",
      "aws:alert_strict",
    ]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful.arn
      priority     = 10
    }
  }
}

resource "aws_networkfirewall_firewall" "lab" {
  count               = var.create_firewall ? 1 : 0
  name                = "${var.name_prefix}-firewall"
  description         = "Optional firewall endpoint for the policy lab"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.lab.arn
  vpc_id              = aws_vpc.lab.id

  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }
}
