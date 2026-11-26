data "aws_partition" "current" {}
data "aws_region" "current" {}

# 1. Enable AWS Security Hub CSPM in a single Region with consolidated control findings
resource "aws_securityhub_account" "this" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

# 2. Subscribe to one official standard: AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "fsbp" {
  count         = var.enable_fsbp_standard ? 1 : 0
  depends_on    = [aws_securityhub_account.this]
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# 3. Safe Security Hub CSPM Automation Rule (enriches INFORMATIONAL findings with a note)
resource "aws_securityhub_automation_rule" "info_note" {
  count       = var.enable_automation_rule ? 1 : 0
  depends_on  = [aws_securityhub_account.this]
  rule_name   = "${var.project_prefix}-info-triage-note"
  description = "Adds a triage note to INFORMATIONAL Security Hub findings in this lab Region."
  rule_order  = 1
  rule_status = "ENABLED"

  criteria {
    severity_label {
      comparison = "EQUALS"
      value      = "INFORMATIONAL"
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
        text       = "Reviewed by Security Hub lab automation rule."
        updated_by = "${var.project_prefix}-automation"
      }
    }
  }
}

# 4. Custom Action -> EventBridge Rule -> Read-Only Triage Lambda
resource "aws_securityhub_action_target" "triage" {
  count       = var.enable_custom_action_pipeline ? 1 : 0
  depends_on  = [aws_securityhub_account.this]
  name        = "Send to Lab Triage"
  identifier  = "SendToLabTriage"
  description = "Sends selected findings to EventBridge and the read-only lab triage Lambda."
}

data "archive_file" "triage_zip" {
  count       = var.enable_custom_action_pipeline ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/triage_handler.py"
  output_path = "${path.module}/build_triage_handler.zip"
}

resource "aws_iam_role" "triage_lambda" {
  count = var.enable_custom_action_pipeline ? 1 : 0
  name  = "${var.project_prefix}-triage-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "triage_logs" {
  count      = var.enable_custom_action_pipeline ? 1 : 0
  role       = aws_iam_role.triage_lambda[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "triage_lambda" {
  count             = var.enable_custom_action_pipeline ? 1 : 0
  name              = "/aws/lambda/${var.project_prefix}-triage-handler"
  retention_in_days = 7
}

resource "aws_lambda_function" "triage" {
  count            = var.enable_custom_action_pipeline ? 1 : 0
  function_name    = "${var.project_prefix}-triage-handler"
  role             = aws_iam_role.triage_lambda[0].arn
  handler          = "triage_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.triage_zip[0].output_path
  source_code_hash = data.archive_file.triage_zip[0].output_base64sha256
  timeout          = 15
  depends_on       = [aws_cloudwatch_log_group.triage_lambda]
}

resource "aws_cloudwatch_event_rule" "custom_action" {
  count       = var.enable_custom_action_pipeline ? 1 : 0
  name        = "${var.project_prefix}-custom-action-rule"
  description = "Routes Security Hub Custom Action events to the read-only triage Lambda."

  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Custom Action"]
    resources     = [aws_securityhub_action_target.triage[0].arn]
  })
}

resource "aws_cloudwatch_event_target" "triage_lambda" {
  count     = var.enable_custom_action_pipeline ? 1 : 0
  rule      = aws_cloudwatch_event_rule.custom_action[0].name
  target_id = "LabTriageLambda"
  arn       = aws_lambda_function.triage[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_custom_action_pipeline ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.triage[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custom_action[0].arn
}
