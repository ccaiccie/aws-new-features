output "vpc_id" {
  value = aws_vpc.lab.id
}

output "firewall_policy_arn" {
  value = aws_networkfirewall_firewall_policy.lab.arn
}

output "firewall_policy_name" {
  value = aws_networkfirewall_firewall_policy.lab.name
}

output "stateful_rule_group_arn" {
  value = aws_networkfirewall_rule_group.stateful.arn
}

output "firewall_arn" {
  value = var.create_firewall ? aws_networkfirewall_firewall.lab[0].arn : null
}

output "firewall_status" {
  value = var.create_firewall ? aws_networkfirewall_firewall.lab[0].firewall_status : null
}
