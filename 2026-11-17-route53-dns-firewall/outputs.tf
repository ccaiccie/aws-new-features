output "vpc_id" {
  description = "Lab VPC. Launch a test instance here to send queries."
  value       = aws_vpc.lab.id
}

output "vpc_resolver_address" {
  description = "The VPC Resolver address (VPC base + 2)."
  value       = cidrhost(var.vpc_cidr, 2)
}

output "rule_group_id" {
  description = "DNS Firewall rule group."
  value       = aws_route53_resolver_firewall_rule_group.lab.id
}

output "query_log_group" {
  description = "CloudWatch log group with Resolver query logs."
  value       = aws_cloudwatch_log_group.dns.name
}

output "test_names" {
  description = "Names to query from an instance in the VPC."
  value = [
    "controldomain1.aggregatelist.firewall.route53resolver.${var.region}.amazonaws.com",
    trimsuffix(var.blocked_domains[0], "."),
    trimsuffix(var.allowed_domains[0], "."),
  ]
}
