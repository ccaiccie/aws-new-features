resource "aws_cloudwatch_log_group" "firewall" {
  for_each          = toset(["FLOW", "ALERT"])
  name              = "/aws/network-firewall/${var.project_name}/${lower(each.key)}"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    dynamic "log_destination_config" {
      for_each = aws_cloudwatch_log_group.firewall
      content {
        log_destination      = { logGroup = log_destination_config.value.name }
        log_destination_type = "CloudWatchLogs"
        log_type             = log_destination_config.key
      }
    }
  }
}
