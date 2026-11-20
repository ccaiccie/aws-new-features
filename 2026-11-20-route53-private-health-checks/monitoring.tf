# Private endpoint health checks are Regional: status, CloudWatch metrics and
# alarms are in the Region of the health check source (this provider's Region),
# not us-east-1 as for public health checks.

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  alarm_name          = "${var.name}-primary-unhealthy"
  alarm_description   = "Route 53 private endpoint health check for the primary (${local.primary}:${var.app_port}${var.health_path}) is unhealthy"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_cloudformation_stack.private_health_checks.outputs["PrimaryCheckId"] }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
