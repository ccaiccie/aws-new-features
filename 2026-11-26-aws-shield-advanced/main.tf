# ==============================================================================
# SAFE SUPPORTING RESOURCES ONLY — NEVER SUBSCRIBES TO AWS SHIELD ADVANCED
# ==============================================================================
# This configuration creates ONLY:
#   1. An Amazon Route 53 HTTPS health check (health-based detection prerequisite)
#   2. An Amazon SNS topic for DDoS alert routing
#   3. An Amazon CloudWatch alarm watching AWS/DDoSProtection -> DDoSDetected
#
# It contains ZERO aws_shield_* resources and CANNOT trigger the $3,000/month
# (1-year commitment) AWS Shield Advanced subscription.
# ==============================================================================

resource "aws_route53_health_check" "app_health" {
  fqdn              = var.health_check_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name    = "${var.project_name}-app-health"
    Purpose = "Shield-Advanced-Health-Based-Detection-Demo"
    Managed = "Terraform-Safe-Lab"
  }
}

resource "aws_sns_topic" "ddos_alerts" {
  name = "${var.project_name}-ddos-alerts"

  tags = {
    Purpose = "Shield-Advanced-CloudWatch-Alarm-Target"
    Managed = "Terraform-Safe-Lab"
  }
}

resource "aws_cloudwatch_metric_alarm" "ddos_detected" {
  alarm_name          = "${var.project_name}-ddos-detected"
  alarm_description   = "Triggers when AWS/DDoSProtection DDoSDetected is non-zero for the monitored resource ARN."
  namespace           = "AWS/DDoSProtection"
  metric_name         = "DDoSDetected"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ResourceArn = var.monitored_resource_arn_placeholder
  }

  alarm_actions = [aws_sns_topic.ddos_alerts.arn]

  tags = {
    Purpose = "Shield-Advanced-Monitoring-Blueprint"
    Managed = "Terraform-Safe-Lab"
  }
}
