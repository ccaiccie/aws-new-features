output "vpc_id" {
  value = aws_vpc.lab.id
}

output "flow_log_id" {
  value = aws_flow_log.cwl.id
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.flow.name
}

output "log_format" {
  description = "The custom record format (version 11, because it includes version 11 fields)."
  value       = local.log_format
}

output "logs_insights_parse" {
  description = "Paste this first line into any Logs Insights query on the log group."
  value       = local.parse_cmd
}

output "web_instance_id" {
  value = aws_instance.web.id
}

output "db_instance_id" {
  value = aws_instance.db.id
}

output "db_private_ip" {
  value = aws_instance.db.private_ip
}

output "nat_gateway_id" {
  value = aws_nat_gateway.nat.id
}

output "nat_gateway_private_ip" {
  value = aws_nat_gateway.nat.private_ip
}

output "s3_bucket" {
  value = var.enable_s3_parquet ? aws_s3_bucket.flow[0].bucket : null
}
