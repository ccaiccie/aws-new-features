# AWS Shield Advanced — Safe Practice Lab (Terraform + AWS CLI)

> **CRITICAL COST & COMMITMENT WARNING — READ BEFORE RUNNING ANYTHING**
>
> **Running this lab MUST NOT subscribe your AWS account to AWS Shield Advanced.**
> AWS Shield Advanced carries an official **$3,000 per month** subscription fee with a **1-year commitment** (auto-renewing annually unless disabled), plus **Data Transfer Out (DTO) usage fees** on protected resources.
>
> - The runnable Terraform configuration in this directory (`main.tf`) creates **only harmless, low-cost supporting resources** (an Amazon Route 53 HTTPS health check, an Amazon SNS topic, and an Amazon CloudWatch metric alarm). **It is impossible to subscribe to AWS Shield Advanced by running `terraform apply` in this folder.**
> - All Shield Advanced subscription, protection, protection-group, and proactive-engagement examples live in `reference-do-not-apply/shield-advanced-reference.tf.example` (a `.example` file in a separate folder that Terraform does not load) and as commented-out reference commands in `cli-examples.sh`.

---

## Official AWS Sources Cited in This Lesson

All architecture facts, limits, prerequisites, and pricing figures in this class and lab were verified against official AWS documentation:

1. Deciding whether to subscribe to AWS Shield Advanced:
   https://docs.aws.amazon.com/waf/latest/developerguide/ddos-advanced-summary-deciding.html
2. Subscribing to AWS Shield Advanced:
   https://docs.aws.amazon.com/waf/latest/developerguide/enable-ddos-prem.html
3. AWS Shield Pricing:
   https://aws.amazon.com/shield/pricing/
4. List of AWS resources that AWS Shield Advanced protects:
   https://docs.aws.amazon.com/waf/latest/developerguide/ddos-advanced-summary-protected-resources.html
5. Grouping your AWS Shield Advanced protections (Protection Groups):
   https://docs.aws.amazon.com/waf/latest/developerguide/ddos-protection-groups.html
6. Health-based detection using health checks with Shield Advanced and Route 53:
   https://docs.aws.amazon.com/waf/latest/developerguide/ddos-advanced-health-checks.html
7. Automating application layer DDoS mitigation with Shield Advanced:
   https://docs.aws.amazon.com/waf/latest/developerguide/ddos-automatic-app-layer-response.html
8. Setting up AWS Shield Response Team (SRT) support:
   https://docs.aws.amazon.com/waf/latest/developerguide/authorize-DRT.html
9. Setting up proactive engagement for the SRT to contact you directly:
   https://docs.aws.amazon.com/waf/latest/developerguide/ddos-srt-proactive-engagement.html
10. Requesting a credit in AWS Shield Advanced after an attack (DDoS Cost Protection):
    https://docs.aws.amazon.com/waf/latest/developerguide/ddos-request-service-credit.html
11. Setting up AWS Firewall Manager AWS Shield Advanced policies:
    https://docs.aws.amazon.com/waf/latest/developerguide/getting-started-fms-shield.html
12. AWS Shield Advanced CloudWatch metrics:
    https://docs.aws.amazon.com/waf/latest/developerguide/shield-metrics.html

---

## Repository Layout

```text
lab/
├── README.md                                            # This guide
├── .gitignore                                           # Excludes .terraform, tfstate, tfvars, secrets
├── versions.tf                                          # Terraform & AWS provider versions
├── variables.tf                                         # Input variables
├── terraform.tfvars.example                             # Safe placeholder values (copy to terraform.tfvars)
├── main.tf                                              # SAFE runnable supporting resources ONLY (never subscribes)
├── outputs.tf                                           # Outputs for safe supporting resources
├── cli-examples.sh                                      # Safe read-only CLI checks + commented DO-NOT-RUN examples
└── reference-do-not-apply/
    └── shield-advanced-reference.tf.example             # Reference-only Shield Advanced Terraform (DO NOT APPLY)
```

---

## Part 1: Running the Safe Supporting Resources Lab

The runnable Terraform in `main.tf` builds the exact supporting observability and health-check foundation you prepare *before* associating protections in a production account:

1. **Amazon Route 53 HTTPS Health Check** (`aws_route53_health_check.app_health`) — demonstrates the external health-check prerequisite required for health-based detection and SRT proactive engagement.
2. **Amazon SNS Topic** (`aws_sns_topic.ddos_alerts`) — notification target for DDoS alarms.
3. **Amazon CloudWatch Metric Alarm** (`aws_cloudwatch_metric_alarm.ddos_detected`) — watches `DDoSDetected` in the `AWS/DDoSProtection` namespace in `us-east-1` (where Shield Advanced publishes global DDoS metrics).

### Steps

```bash
# 1. Copy the example variables file and edit placeholders if desired
cp terraform.tfvars.example terraform.tfvars

# 2. Initialize and inspect the execution plan
terraform init
terraform plan

# Verify the plan shows ONLY:
#   - aws_route53_health_check.app_health
#   - aws_sns_topic.ddos_alerts
#   - aws_cloudwatch_metric_alarm.ddos_detected
# Confirm ZERO aws_shield_* resources appear in the plan.

# 3. Apply the safe supporting resources
terraform apply
```

---

## Part 2: Safe Read-Only AWS CLI Verification

You can safely run read-only Shield CLI commands in `us-east-1` (the Shield control-plane region) without subscribing or incurring charges:

```bash
# Check whether the current account is subscribed (returns ACTIVE or INACTIVE)
aws shield get-subscription-state --region us-east-1

# List any protected resources (returns empty or NotSubscribedException if inactive)
aws shield list-protections --region us-east-1
```

See `cli-examples.sh` for the full set of read-only commands and clearly commented-out `DO-NOT-RUN` write/subscription examples.

---

## Part 3: Reference-Only Shield Advanced Terraform (DO NOT APPLY)

Study `reference-do-not-apply/shield-advanced-reference.tf.example` to see how production teams codify:
- `aws_shield_subscription` (with `auto_renew = "DISABLED"` option — **$3,000/month, 1-year commitment**)
- `aws_shield_protection` (explicit resource protection — subscribing alone does not protect resources)
- `aws_shield_protection_group` (logical grouping by `ALL`, `ARBITRARY`, or `BY_RESOURCE_TYPE`)
- `aws_shield_protection_health_check_association` (associating a healthy Route 53 health check)
- `aws_shield_drt_access_role_arn_association` (authorizing `drt.shield.amazonaws.com` with `AWSShieldDRTAccessPolicy`)
- `aws_shield_proactive_engagement` (enabling SRT proactive outreach with emergency contacts)

**Never rename or copy that file into `lab/` unless your organization has formally approved the $3,000/month, 1-year Shield Advanced subscription commitment.**

---

## Part 4: Tear-Down / Cleanup

When you finish testing the safe supporting resources, destroy them immediately so you do not pay ongoing Route 53 health-check charges (~$0.50/month per basic AWS endpoint health check):

```bash
terraform destroy
```

Confirm all 3 resources (`aws_cloudwatch_metric_alarm`, `aws_sns_topic`, `aws_route53_health_check`) are destroyed, and verify no local `.tfstate` or `terraform.tfvars` files with sensitive values are committed to Git.
