# Security Hub and GuardDuty: from threat finding to response

Terraform practice lab for the AWS New Features video "AWS Security Hub + Amazon GuardDuty: From Threat Finding to Response" (YouTube playlist **aws new features**, Network Technician channel).

GuardDuty is the **detector** (CloudTrail management events, an independent copy of VPC Flow Logs, Route 53 Resolver DNS query logs). Security Hub is the **aggregation and posture layer**: Security Hub CSPM (standards, controls, ASFF) and the unified AWS Security Hub (OCSF, exposure findings, correlation). Neither one sits in the traffic path; blocking is still done by security groups, NACLs, AWS Network Firewall, AWS WAF and Route 53 Resolver DNS Firewall.

## What it builds

| Piece | Resource | Why it matters |
| --- | --- | --- |
| GuardDuty detector, 15-minute publishing | `aws_guardduty_detector` | Foundational sources start immediately; no flow logs or query logging needed in your account |
| Protection plans | `aws_guardduty_detector_feature` (`S3_DATA_EVENTS`, `EBS_MALWARE_PROTECTION`, `LAMBDA_NETWORK_LOGS`; optional `RUNTIME_MONITORING` with `EC2_AGENT_MANAGEMENT`) | Each plan is an extra data source; Lambda network logs matter to network teams |
| Suppression rule | `aws_guardduty_filter` (`ARCHIVE`) | Auto-archives `Recon:EC2/PortProbeUnprotectedPort` from your own scanner; archived findings are not sent to Security Hub CSPM |
| Custom threat list | `aws_s3_bucket`, `aws_s3_object`, `aws_guardduty_threatintelset` | Documentation-range IPs; matches produce `*.Custom` findings |
| Security Hub CSPM | `aws_securityhub_account` (no default standards, consolidated control findings) | The posture layer; receives GuardDuty findings in ASFF |
| Standards | `aws_securityhub_standards_subscription` for FSBP v1.0.0 and CIS AWS Foundations Benchmark v5.0.0 | Includes network controls such as EC2.2, EC2.6, EC2.19 and GuardDuty.1 |
| Automation rule | `aws_securityhub_automation_rule` | GuardDuty findings that are HIGH or CRITICAL and NEW become NOTIFIED with a note for network on-call |
| Custom action | `aws_securityhub_action_target` | "Send to NetOps" button in the CSPM console (EventBridge `Security Hub Findings - Custom Action`) |
| Three EventBridge rules | `aws_cloudwatch_event_rule` + targets to SNS and CloudWatch Logs | `GuardDuty Finding` (native, network types, severity >= 4), `Security Hub Findings - Imported` (ASFF), optional `Findings Imported V2` (OCSF) |
| Optional unified Security Hub | `aws_securityhub_account_v2`, `aws_securityhub_feature_v2` (`NETWORK_SCANNING`) | OCSF findings, exposures, and Network Scanning of public IPs, instances and load balancers |
| Optional delegated admin | `aws_guardduty_organization_admin_account`, `aws_securityhub_organization_admin_account` | Only from an Organizations management account |

## Prerequisites

An AWS account (ideally a sandbox), credentials for Terraform, Terraform 1.6+, provider `hashicorp/aws` 6.73.0. If GuardDuty or Security Hub CSPM is already enabled in the account and Region (for example by your organization's delegated admin), import the existing detector and hub or use a different sandbox account, because a Region can only have one detector.

## Cost warning

GuardDuty has a 30-day free trial per Region, then bills by analyzed volume. Security Hub CSPM bills per control check and per ingested finding. Runtime Monitoring and the unified Security Hub plans add cost. **Run `terraform destroy` when you finish.** Destroy disables Security Hub CSPM and deletes the detector, which also deletes its findings.

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
terraform apply
terraform output
```

Generate sample findings (they are clearly marked as samples), including the network types from the video:

```bash
DET=$(terraform output -raw detector_id)
aws guardduty create-sample-findings --detector-id "$DET" \
  --finding-types "Recon:EC2/PortProbeUnprotectedPort" "CryptoCurrency:EC2/BitcoinTool.B!DNS" \
                  "Backdoor:EC2/C&CActivity.B!DNS" "Trojan:EC2/DNSDataExfiltration"
```

Then watch them arrive:

```bash
# 1) Native GuardDuty events and Security Hub CSPM events in the log group
aws logs tail "$(terraform output -raw event_log_group)" --since 30m --follow

# 2) The same findings in Security Hub CSPM (ASFF), with the automation rule's note and workflow status
aws securityhub get-findings --filters '{"ProductName":[{"Value":"GuardDuty","Comparison":"EQUALS"}]}' \
  --query "Findings[].[Types[0],Severity.Label,Workflow.Status,Note.Text]" --output table
```

GuardDuty usually sends a new finding to Security Hub CSPM within about five minutes.

## Experiments

1. Compare the three event shapes in the log group: native GuardDuty JSON, ASFF (`Security Hub Findings - Imported`) and, with `enable_security_hub_v2 = true`, OCSF (`Findings Imported V2`). A rule that matches only `source = aws.securityhub` would receive both hub formats.
2. Set `trusted_scanner_ip` to the remote IP shown in a sample port-probe finding, apply, and generate the sample again: the new finding is archived in GuardDuty and does not reach Security Hub CSPM.
3. Change the automation rule to set `workflow.status = "SUPPRESSED"` for LOW findings and see which network findings disappear from the default view.
4. With `enable_security_hub_v2 = true` and `enable_network_scanning = true`, compare Network Scanning findings (actually reachable ports) with CSPM control EC2.19 (security groups that allow high-risk ports).

## What Terraform cannot do here (limitations, stated plainly)

- **No real attacks.** Terraform cannot make GuardDuty detect a real port probe or mining domain. Use `create-sample-findings` as above.
- **GuardDuty product subscription is automatic.** When GuardDuty and Security Hub CSPM are both enabled in the same account and Region, the integration turns on by itself. `aws_securityhub_product_subscription` for `product/aws/guardduty` is behind `enable_guardduty_product_subscription` (default `false`) because re-enabling it can return a conflict.
- **No automatic blocking in this lab.** The video's response playbook (EventBridge -> Lambda -> Network Firewall rule group or WAF IP set) needs your own Lambda code and an existing firewall; this lab stops at SNS and CloudWatch Logs so nothing in your network changes.
- **Unified Security Hub decisions are console decisions.** Provider 6.73.0 has `aws_securityhub_account_v2`, `aws_securityhub_aggregator_v2`, `aws_securityhub_feature_v2` and `aws_securityhub_automation_rule_v2`, but plan choices (Essentials, add-ons), pricing and the trends dashboard are managed in the console. The lab does not include an OCSF automation rule (`aws_securityhub_automation_rule_v2`); build one in the console and compare it with the ASFF rule here.
- **Organization setup is partial.** The delegated-admin resources only work from the management account. Note that the management account can be its own delegated admin for Security Hub CSPM but not for the unified Security Hub, and GuardDuty delegated admin and auto-enable (`aws_guardduty_organization_configuration`) are per Region. Central configuration policies (`aws_securityhub_configuration_policy`) are not in this lab.
- **Single Region.** Cross-Region aggregation (`aws_securityhub_finding_aggregator` / `aws_securityhub_aggregator_v2`) is not configured.

## Clean up

```bash
terraform destroy
```

## Sources

- GuardDuty foundational data sources: https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_data-sources.html
- GuardDuty integration with Security Hub CSPM: https://docs.aws.amazon.com/guardduty/latest/ug/securityhub-integration.html
- GuardDuty finding types: https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_finding-types-active.html
- Security Hub FAQ (Security Hub vs Security Hub CSPM): https://aws.amazon.com/security-hub/faqs/
- Security Hub EventBridge rules (Findings Imported V2): https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-v2-cwe-event-rules.html
- Security Hub delegated administrator: https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-v2-set-da.html
- Security Hub Network Scanning: https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-v2-network-scanning.html
- Running vulnerable software in exposure findings (Nov 16, 2026): https://aws.amazon.com/about-aws/whats-new/2026/11/security-hub-detects-vulnerable-software/
