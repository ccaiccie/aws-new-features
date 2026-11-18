data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  region  = data.aws_region.current.region
  account = data.aws_caller_identity.current.account_id
  part    = data.aws_partition.current.partition
}

############################
# Amazon GuardDuty: detect #
############################

# Foundational sources (CloudTrail management events, VPC Flow Logs, Route 53 Resolver DNS logs)
# start as soon as the detector is enabled. No flow logs or query logging are needed in your account.
resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency
  tags                         = { Lab = var.name_prefix }
}

resource "aws_guardduty_detector_feature" "plans" {
  for_each    = toset(var.enable_protection_features)
  detector_id = aws_guardduty_detector.this.id
  name        = each.value
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "runtime" {
  count       = var.enable_runtime_monitoring ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "EC2_AGENT_MANAGEMENT"
    status = "ENABLED"
  }
}

# Suppression rule: auto-archive port probes that come from your own scanner.
# Archived findings are not sent on to Security Hub CSPM.
resource "aws_guardduty_filter" "trusted_scanner" {
  name        = "${var.name_prefix}-trusted-scanner"
  detector_id = aws_guardduty_detector.this.id
  action      = "ARCHIVE"
  rank        = 1
  description = "Auto-archive port probes from the internal vulnerability scanner"

  finding_criteria {
    criterion {
      field  = "type"
      equals = ["Recon:EC2/PortProbeUnprotectedPort"]
    }
    criterion {
      field  = "service.action.portProbeAction.portProbeDetails.remoteIpDetails.ipAddressV4"
      equals = [var.trusted_scanner_ip]
    }
  }
}

# Custom threat list (plain text, one IP or CIDR per line) -> *.Custom findings
resource "aws_s3_bucket" "lists" {
  bucket_prefix = "${var.name_prefix}-gd-lists-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lists" {
  bucket                  = aws_s3_bucket.lists.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "threat_list" {
  bucket       = aws_s3_bucket.lists.id
  key          = "threat-list.txt"
  content      = join("\n", var.threat_list_ips)
  content_type = "text/plain"
}

resource "aws_guardduty_threatintelset" "lab" {
  name        = "${var.name_prefix}-threats"
  detector_id = aws_guardduty_detector.this.id
  activate    = true
  format      = "TXT"
  location    = "https://s3.amazonaws.com/${aws_s3_object.threat_list.bucket}/${aws_s3_object.threat_list.key}"
}

########################################
# AWS Security Hub CSPM: posture + ASFF #
########################################

resource "aws_securityhub_account" "this" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:${local.part}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_cis_standard ? 1 : 0
  standards_arn = "arn:${local.part}:securityhub:${local.region}::standards/cis-aws-foundations-benchmark/v/5.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# The GuardDuty -> Security Hub CSPM integration turns on automatically when both are enabled.
# Kept optional because re-enabling an already-enabled integration can return a conflict.
resource "aws_securityhub_product_subscription" "guardduty" {
  count       = var.enable_guardduty_product_subscription ? 1 : 0
  product_arn = "arn:${local.part}:securityhub:${local.region}::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.this]
}

# Automation rule: high and critical GuardDuty findings -> NOTIFIED + note for network on-call
resource "aws_securityhub_automation_rule" "gd_high_to_netops" {
  rule_name   = "${var.name_prefix}-guardduty-high-to-netops"
  description = "Mark high and critical GuardDuty findings as NOTIFIED and tag network on-call"
  rule_order  = 1
  rule_status = "ENABLED"

  criteria {
    product_name {
      comparison = "EQUALS"
      value      = "GuardDuty"
    }
    severity_label {
      comparison = "EQUALS"
      value      = "HIGH"
    }
    severity_label {
      comparison = "EQUALS"
      value      = "CRITICAL"
    }
    workflow_status {
      comparison = "EQUALS"
      value      = "NEW"
    }
  }

  actions {
    type = "FINDING_FIELDS_UPDATE"
    finding_fields_update {
      note {
        text       = "Network on-call owns this GuardDuty finding (lab automation rule)."
        updated_by = "terraform-lab"
      }
      workflow {
        status = "NOTIFIED"
      }
    }
  }

  depends_on = [aws_securityhub_account.this]
}

# Custom action: analysts pick findings in the console and "Send to NetOps" (EventBridge: Security Hub Findings - Custom Action)
resource "aws_securityhub_action_target" "netops" {
  name        = "Send to NetOps"
  identifier  = "SendToNetOps"
  description = "Send selected findings to the network team"
  depends_on  = [aws_securityhub_account.this]
}

######################################
# Optional: unified Security Hub (v2) #
######################################

resource "aws_securityhub_account_v2" "this" {
  count = var.enable_security_hub_v2 ? 1 : 0
}

resource "aws_securityhub_feature_v2" "network_scanning" {
  count          = var.enable_security_hub_v2 && var.enable_network_scanning ? 1 : 0
  feature_name   = "NETWORK_SCANNING"
  feature_status = "ENABLED"
  depends_on     = [aws_securityhub_account_v2.this]
}

#########################################################
# Optional: delegated admin (run from management account) #
#########################################################

resource "aws_guardduty_organization_admin_account" "this" {
  count            = var.delegated_admin_account_id != "" ? 1 : 0
  admin_account_id = var.delegated_admin_account_id
  depends_on       = [aws_guardduty_detector.this]
}

resource "aws_securityhub_organization_admin_account" "this" {
  count            = var.delegated_admin_account_id != "" ? 1 : 0
  admin_account_id = var.delegated_admin_account_id
  depends_on       = [aws_securityhub_account.this]
}
