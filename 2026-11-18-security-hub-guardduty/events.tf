##########################################
# EventBridge: three different event types #
##########################################

resource "aws_sns_topic" "findings" {
  name = "${var.name_prefix}-findings"
}

data "aws_iam_policy_document" "sns_events" {
  statement {
    sid       = "AllowEventBridgePublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.findings.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "findings" {
  arn    = aws_sns_topic.findings.arn
  policy = data.aws_iam_policy_document.sns_events.json
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.findings.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_group" "findings" {
  name              = "/aws/events/${var.name_prefix}-findings"
  retention_in_days = 7
}

data "aws_iam_policy_document" "logs_events" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.findings.arn}:*"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "events" {
  policy_name     = "${var.name_prefix}-events-to-logs"
  policy_document = data.aws_iam_policy_document.logs_events.json
}

locals {
  rules = merge(
    {
      # 1) Native GuardDuty events: network finding types, medium severity (4.0) and up
      guardduty_network = jsonencode({
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
        detail = {
          type = [
            { prefix = "Recon:EC2/" },
            { prefix = "Backdoor:EC2/" },
            { prefix = "CryptoCurrency:EC2/" },
            { prefix = "Trojan:EC2/" },
            { prefix = "UnauthorizedAccess:EC2/" }
          ]
          severity = [{ numeric = [">=", 4] }]
        }
      })
      # 2) Security Hub CSPM (ASFF): GuardDuty findings, HIGH or CRITICAL
      cspm_guardduty = jsonencode({
        source        = ["aws.securityhub"]
        "detail-type" = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            ProductName = ["GuardDuty"]
            Severity    = { Label = ["HIGH", "CRITICAL"] }
          }
        }
      })
    },
    var.enable_security_hub_v2 ? {
      # 3) Unified Security Hub (OCSF): GuardDuty findings
      v2_guardduty = jsonencode({
        source        = ["aws.securityhub"]
        "detail-type" = ["Findings Imported V2"]
        detail = {
          findings = {
            metadata = { product = { name = ["GuardDuty"] } }
          }
        }
      })
    } : {}
  )
}

resource "aws_cloudwatch_event_rule" "findings" {
  for_each      = local.rules
  name          = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  description   = "Lab rule: ${each.key}"
  event_pattern = each.value
}

resource "aws_cloudwatch_event_target" "sns" {
  for_each = local.rules
  rule     = aws_cloudwatch_event_rule.findings[each.key].name
  arn      = aws_sns_topic.findings.arn
}

resource "aws_cloudwatch_event_target" "logs" {
  for_each = local.rules
  rule     = aws_cloudwatch_event_rule.findings[each.key].name
  arn      = aws_cloudwatch_log_group.findings.arn
}
