# ---------------------------------------------------------------- Alerting on ImpactScore
# Performance Monitor publishes per-path metrics in AWS/NetworkFlowMonitor with the dimensions
# MonitorId, LocalLocation and RemoteLocation. There is no monitor-level metric, so the
# documented way to alarm on "any path" is a CloudWatch Metrics Insights query.
locals {
  have_monitor = var.performance_monitor_id != ""
  any_path_query = format(
    "SELECT MAX(ImpactScore) FROM SCHEMA(\"AWS/NetworkFlowMonitor\", LocalLocation, MonitorId, RemoteLocation) WHERE MonitorId = '%s'",
    var.performance_monitor_id
  )
}

resource "aws_sns_topic" "network_health" {
  name = "${var.name_prefix}-network-health"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.network_health.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "any_path_impact" {
  count = local.have_monitor ? 1 : 0

  alarm_name          = "${var.name_prefix}-any-path-impact-${var.impact_alarm_threshold}"
  alarm_description   = "Any network path in performance monitor ${var.performance_monitor_id} reached ImpactScore >= ${var.impact_alarm_threshold} (65 = Medium, 95 = High)."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.impact_alarm_threshold
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.network_health.arn]
  ok_actions          = [aws_sns_topic.network_health.arn]

  metric_query {
    id          = "maximpact"
    expression  = local.any_path_query
    period      = 300
    label       = "Highest ImpactScore across paths"
    return_data = true
  }
}

resource "aws_cloudwatch_dashboard" "paths" {
  count          = local.have_monitor ? 1 : 0
  dashboard_name = "${var.name_prefix}-network-paths"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ImpactScore by path (0 None, 25 Low, 65 Medium, 95 High)"
          region  = var.region
          view    = "timeSeries"
          stat    = "Maximum"
          period  = 300
          metrics = [[{ id = "q1", expression = "SELECT MAX(ImpactScore) FROM SCHEMA(\"AWS/NetworkFlowMonitor\", LocalLocation, MonitorId, RemoteLocation) WHERE MonitorId = '${var.performance_monitor_id}' GROUP BY LocalLocation, RemoteLocation", label = "" }]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "p95 round-trip time by path (ms)"
          region  = var.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 300
          metrics = [[{ id = "q2", expression = "SELECT AVG(RoundTripTimeP95Ms) FROM SCHEMA(\"AWS/NetworkFlowMonitor\", LocalLocation, MonitorId, RemoteLocation) WHERE MonitorId = '${var.performance_monitor_id}' GROUP BY LocalLocation, RemoteLocation", label = "" }]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title   = "Bytes out by path"
          region  = var.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 300
          metrics = [[{ id = "q3", expression = "SELECT SUM(BytesOut) FROM SCHEMA(\"AWS/NetworkFlowMonitor\", LocalLocation, MonitorId, RemoteLocation) WHERE MonitorId = '${var.performance_monitor_id}' GROUP BY LocalLocation, RemoteLocation", label = "" }]]
        }
      }
    ]
  })
}
