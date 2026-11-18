# ---------------------------------------------------------------- Isolation security group (optional)
# GuardDuty remediation guidance: a dedicated isolation group with no 0.0.0.0/0 rules.
# With no ingress or egress blocks, Terraform also removes the default allow-all egress rule.
resource "aws_security_group" "isolation" {
  count       = var.isolation_vpc_id == "" ? 0 : 1
  name        = "${var.name_prefix}-isolation"
  description = "Isolation group for potentially compromised instances (no rules)"
  vpc_id      = var.isolation_vpc_id
}

# ---------------------------------------------------------------- Lambda responder
data "archive_file" "responder" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/responder.zip"
}

resource "aws_iam_role" "responder" {
  name = "${var.name_prefix}-responder"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "responder_logs" {
  role       = aws_iam_role.responder.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "responder_isolate" {
  count = var.isolation_vpc_id == "" ? 0 : 1
  name  = "isolate-instances"
  role  = aws_iam_role.responder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["ec2:ModifyInstanceAttribute"]
        Resource = [
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*",
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:security-group/${aws_security_group.isolation[0].id}"
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "responder" {
  name              = "/aws/lambda/${var.name_prefix}-responder"
  retention_in_days = 7
}

resource "aws_lambda_function" "responder" {
  function_name    = "${var.name_prefix}-responder"
  role             = aws_iam_role.responder.arn
  runtime          = "python3.13"
  handler          = "handler.handler"
  filename         = data.archive_file.responder.output_path
  source_code_hash = data.archive_file.responder.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ISOLATE                = var.enable_isolation && var.isolation_vpc_id != "" ? "true" : "false"
      ISOLATION_SG_ID        = var.isolation_vpc_id == "" ? "" : aws_security_group.isolation[0].id
      ISOLATION_VPC_ID       = var.isolation_vpc_id
      ISOLATION_MIN_SEVERITY = tostring(var.isolation_min_severity)
    }
  }

  depends_on = [aws_cloudwatch_log_group.responder, aws_iam_role_policy_attachment.responder_logs]
}

# ---------------------------------------------------------------- EventBridge rules
locals {
  rules = {
    guardduty = {
      description = "Native GuardDuty findings at or above the chosen severity"
      pattern = {
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
        detail        = { severity = [{ numeric = [">=", var.guardduty_min_severity] }] }
      }
    }
    macie = {
      description = "Native Macie findings (policy and sensitive data)"
      pattern = {
        source        = ["aws.macie"]
        "detail-type" = ["Macie Finding"]
      }
    }
    securityhub = {
      description = "Security Hub CSPM imported findings (ASFF) from GuardDuty and Macie"
      pattern = {
        source        = ["aws.securityhub"]
        "detail-type" = ["Security Hub Findings - Imported"]
        detail        = { findings = { ProductName = ["GuardDuty", "Macie"] } }
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each      = local.rules
  name          = "${var.name_prefix}-${each.key}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.rules
  rule     = aws_cloudwatch_event_rule.this[each.key].name
  arn      = aws_lambda_function.responder.arn
}

resource "aws_lambda_permission" "events" {
  for_each      = local.rules
  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.responder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[each.key].arn
}
