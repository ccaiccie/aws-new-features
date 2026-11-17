# Route 53 Resolver DNS Firewall: domain lists, actions and Advanced rules

Terraform practice lab for the AWS New Features video "Route 53 Resolver DNS Firewall: Domain Lists, Actions and Advanced Rules" (YouTube playlist **aws new features**, Network Technician channel).

## What it builds

| Piece | Why it matters |
| --- | --- |
| VPC with DNS support | Instances query the VPC Resolver at the VPC base address + 2 |
| Two custom domain lists (block, allow) | Reusable name sets; entries may start with `*` |
| Rule group with four rules | 100 ALLOW exceptions, 200 BLOCK managed aggregate list (NXDOMAIN, optional), 300 BLOCK custom list (OVERRIDE CNAME), 400 Advanced DNS tunneling (ALERT, MEDIUM) |
| Association at priority 101 | Turns filtering on for the VPC; lowest priority number is evaluated first |
| `aws_route53_resolver_firewall_config` | Fail closed (`DISABLED`, default) or fail open (`ENABLED`), set explicitly |
| Resolver query logging to CloudWatch Logs | ALERT and BLOCK actions are logged with the rule group, action and domain list |

## Prerequisites

An AWS account, credentials for Terraform, Terraform 1.6+, provider `hashicorp/aws` 6.73.0.

Rule 200 needs the ID of the AWS managed aggregate list in your Region (managed list IDs differ per Region):

```bash
aws route53resolver list-firewall-domain-lists --region us-east-1 \
  --query "FirewallDomainLists[?Name=='AWSManagedDomainsAggregateThreatList'].Id" --output text
```

Put the value in `managed_aggregate_list_id`. Leave it empty to skip rule 200.

## Cost warning

DNS Firewall is billed per domain in your own lists and per query processed; query logs are billed by CloudWatch Logs. The lab does not create an instance — launch a small one yourself in the VPC to test, and terminate it. **Run `terraform destroy` when you finish.**

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
terraform apply
terraform output test_names
```

From an instance in the lab VPC (it needs an SSM or SSH path you add yourself):

```bash
dig controldomain1.aggregatelist.firewall.route53resolver.us-east-1.amazonaws.com   # NXDOMAIN if rule 200 is on, otherwise 1.2.3.4
dig blocked.example.com                                                             # CNAME sinkhole.example.com (OVERRIDE)
dig partner.example.org                                                             # normal answer (ALLOW at 100)
```

Then open the CloudWatch log group from `terraform output query_log_group` and find the `firewall_rule_action` values.

## Experiments

1. Move the ALLOW rule to priority 500 and add `partner.example.org.` to the block list. Observe that the block at 300 now wins.
2. Switch rule 300 to `block_response = "NODATA"` and compare the `dig` output.
3. Set `tunneling_action = "BLOCK"` after reviewing the alerts.
4. Set `firewall_fail_open = "ENABLED"` and discuss when availability should win over security.
5. Set `mutation_protection = "ENABLED"` on the association and try to delete it.

## References

- How Resolver DNS Firewall works — https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-dns-firewall-overview.html
- Rule actions — https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-dns-firewall-rule-actions.html
- Managed domain lists — https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-dns-firewall-managed-domain-lists.html
- VPC configuration (fail mode) — https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-dns-firewall-vpc-configuration.html
