output "aws_region" {
  description = "AWS Region used for the ALB and regional web ACL."
  value       = var.aws_region
}

output "cloudfront_domain_name" {
  description = "Amazon CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.lab.domain_name
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name."
  value       = aws_lb.lab.dns_name
}

output "cf_log_group_name" {
  description = "CloudWatch Logs group for CloudFront global web ACL (in us-east-1)."
  value       = aws_cloudwatch_log_group.cf_waf.name
}

output "alb_log_group_name" {
  description = "CloudWatch Logs group for ALB regional web ACL."
  value       = aws_cloudwatch_log_group.alb_waf.name
}
