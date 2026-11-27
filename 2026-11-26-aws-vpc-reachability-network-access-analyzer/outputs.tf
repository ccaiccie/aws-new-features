output "vpc_id" {
  description = "Disposable lab VPC ID"
  value       = aws_vpc.lab.id
}

output "igw_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.lab.id
}

output "web_instance_id" {
  description = "Web tier EC2 instance ID"
  value       = aws_instance.web.id
}

output "app_instance_id" {
  description = "App tier EC2 instance ID"
  value       = aws_instance.app.id
}

output "db_instance_id" {
  description = "DB tier EC2 instance ID"
  value       = aws_instance.db.id
}

output "working_path_id" {
  description = "Reachability Analyzer path ID for working web -> app TCP 443 path"
  value       = aws_ec2_network_insights_path.working_web_to_app.id
}

output "blocked_path_id" {
  description = "Reachability Analyzer path ID for blocked app -> db TCP 5432 path"
  value       = aws_ec2_network_insights_path.blocked_app_to_db.id
}
