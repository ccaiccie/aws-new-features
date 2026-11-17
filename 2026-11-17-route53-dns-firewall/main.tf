# ---------------------------------------------------------------------------
# A small VPC with DNS support. Instances use the VPC Resolver (base + 2).
# ---------------------------------------------------------------------------
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# ---------------------------------------------------------------------------
# Domain lists: one block list, one allow (exception) list.
# ---------------------------------------------------------------------------
resource "aws_route53_resolver_firewall_domain_list" "blocked" {
  name    = "${var.name_prefix}-blocked"
  domains = var.blocked_domains
}

resource "aws_route53_resolver_firewall_domain_list" "allowed" {
  name    = "${var.name_prefix}-allowed"
  domains = var.allowed_domains
}

# ---------------------------------------------------------------------------
# Rule group and rules. Lowest priority number is evaluated first;
# the first match wins; no match = resolve normally.
# ---------------------------------------------------------------------------
resource "aws_route53_resolver_firewall_rule_group" "lab" {
  name = "${var.name_prefix}-rules"
}

# 100: exceptions first
resource "aws_route53_resolver_firewall_rule" "allow_exceptions" {
  name                    = "allow-exceptions"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.lab.id
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.allowed.id
  priority                = 100
  action                  = "ALLOW"
}

# 200: AWS managed aggregate threat list, NXDOMAIN
resource "aws_route53_resolver_firewall_rule" "block_managed_aggregate" {
  count                   = var.managed_aggregate_list_id == "" ? 0 : 1
  name                    = "block-managed-aggregate"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.lab.id
  firewall_domain_list_id = var.managed_aggregate_list_id
  priority                = 200
  action                  = "BLOCK"
  block_response          = "NXDOMAIN"
}

# 300: custom block list, OVERRIDE with a CNAME
resource "aws_route53_resolver_firewall_rule" "block_custom_override" {
  name                    = "block-custom-override"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.lab.id
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.blocked.id
  priority                = 300
  action                  = "BLOCK"
  block_response          = "OVERRIDE"
  block_override_dns_type = "CNAME"
  block_override_domain   = var.override_cname
  block_override_ttl      = 0
}

# 400: DNS Firewall Advanced - DNS tunneling protection
resource "aws_route53_resolver_firewall_rule" "advanced_tunneling" {
  name                   = "advanced-dns-tunneling"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.lab.id
  priority               = 400
  action                 = var.tunneling_action
  dns_threat_protection  = "DNS_TUNNELING"
  confidence_threshold   = var.tunneling_confidence
}

# ---------------------------------------------------------------------------
# Associate the rule group with the VPC (leave gaps: 101, 200, ...).
# ---------------------------------------------------------------------------
resource "aws_route53_resolver_firewall_rule_group_association" "lab" {
  name                   = "${var.name_prefix}-assoc"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.lab.id
  vpc_id                 = aws_vpc.lab.id
  priority               = 101
  mutation_protection    = "DISABLED"
}

# Fail closed (DISABLED) or fail open (ENABLED), set explicitly.
resource "aws_route53_resolver_firewall_config" "lab" {
  resource_id        = aws_vpc.lab.id
  firewall_fail_open = var.firewall_fail_open
}

# ---------------------------------------------------------------------------
# Resolver query logging: ALERT and BLOCK actions show up here.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "dns" {
  name              = "/${var.name_prefix}/resolver-query-logs"
  retention_in_days = var.log_retention_days
}

resource "aws_route53_resolver_query_log_config" "lab" {
  name            = "${var.name_prefix}-qlog"
  destination_arn = aws_cloudwatch_log_group.dns.arn
}

resource "aws_route53_resolver_query_log_config_association" "lab" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.lab.id
  resource_id                  = aws_vpc.lab.id
}
