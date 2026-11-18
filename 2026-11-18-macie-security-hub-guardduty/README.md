# Macie, Security Hub and GuardDuty: one security pipeline

Terraform practice lab for the AWS New Features video "Macie, Security Hub and GuardDuty: how they work together" (YouTube playlist **aws new features**, Network Technician channel).

The three services form a layered pipeline:

| Layer | Service | What it does |
| --- | --- | --- |
| Detect | Amazon GuardDuty | Threat detection from CloudTrail management events, an independent copy of VPC Flow Logs, and Route 53 Resolver DNS query logs (plus optional protection plans) |
| Discover | Amazon Macie | S3 bucket inventory and security monitoring (policy findings) and sensitive data discovery in objects (sensitive data findings) |
| Aggregate | AWS Security Hub CSPM | Receives GuardDuty and Macie findings in ASFF, runs standards and controls, emits EventBridge events |
| Respond | Amazon EventBridge + AWS Lambda | Rules match findings and invoke a function (or Systems Manager, SNS, SQS, Step Functions) |

Naming: AWS now documents **Security Hub CSPM** (formerly Security Hub: standards, controls, ASFF, `Security Hub Findings - Imported`) and the newer unified **AWS Security Hub** (OCSF, exposure findings, `Findings Imported V2`). This lab uses Security Hub CSPM as the aggregator. The sibling lab [`2026-11-18-security-hub-guardduty`](../2026-11-18-security-hub-guardduty) shows the unified Security Hub resources.

None of these services sits in the traffic path. Blocking is still done by security groups, network ACLs and firewalls.

## What it builds

| Piece | Resource | Why it matters |
| --- | --- | --- |
| GuardDuty detector, 15-minute publishing | `aws_guardduty_detector` | Foundational sources start immediately; no flow logs or query logging needed in your account |
| Macie | `aws_macie2_account` | Starts the S3 bucket inventory and policy findings |
| Lab bucket with **fake** data | `aws_s3_bucket`, `aws_s3_bucket_public_access_block`, `aws_s3_object` | Test card numbers (4111..., 5555...), example.com emails, 555 phone numbers, made-up employee IDs |
| Custom data identifier | `aws_macie2_custom_data_identifier` | Regex `EMP-[0-9]{6}` + keyword `employee id` + 50-character proximity |
| One-time discovery job (optional, default on) | `aws_macie2_classification_job` (`ONE_TIME`) | Produces sensitive data findings for the lab bucket |
| Security Hub CSPM | `aws_securityhub_account`, `aws_securityhub_standards_subscription` (FSBP v1.0.0) | The aggregator; GuardDuty and Macie integrations turn on automatically |
| Optional Macie product subscription | `aws_securityhub_product_subscription` | Normally unnecessary (automatic integration); off by default because it can conflict |
| Lambda responder | `aws_lambda_function` (Python 3.13), `aws_iam_role`, `aws_cloudwatch_log_group` | Logs a one-line summary of every finding; optional isolation |
| Three EventBridge rules | `aws_cloudwatch_event_rule`, `aws_cloudwatch_event_target`, `aws_lambda_permission` | `GuardDuty Finding` (severity >= 4), `Macie Finding`, and `Security Hub Findings - Imported` filtered to GuardDuty and Macie |
| Optional isolation security group | `aws_security_group` (no rules) | Set `isolation_vpc_id` and `enable_isolation = true` to let the function swap an instance into it |
| Optional delegated admin | `aws_guardduty_organization_admin_account`, `aws_macie2_organization_admin_account`, `aws_securityhub_organization_admin_account` | Only from an Organizations management account, in this Region |

## Prerequisites

An AWS account (ideally a sandbox), credentials for Terraform, Terraform 1.6+, providers `hashicorp/aws` 6.73.0 and `hashicorp/archive` 2.7.1 (to zip the Lambda code). If GuardDuty, Macie or Security Hub CSPM is already enabled in the account and Region (for example by your organization's delegated admin, or by the sibling lab), import the existing resources or use a different sandbox account: a Region can have only one GuardDuty detector, and Macie and Security Hub CSPM are one-per-account-per-Region too.

Security Hub CSPM controls need **AWS Config** recording resources in the Region. This lab does not create a Config recorder; without one, FSBP control checks will not produce useful results, but GuardDuty and Macie findings still flow into Security Hub CSPM.

## Cost warning

Each service has a 30-day free trial per account and Region. Afterwards GuardDuty bills by analyzed volume, Macie bills for bucket monitoring, automated discovery and data analyzed by jobs (jobs are **not** covered by the Macie free trial; the lab bucket is tiny), and Security Hub CSPM bills for control checks and ingested findings, plus AWS Config items if you enable Config. **Run `terraform destroy` when you finish.**

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
terraform apply
terraform output
```

### 1. Let Macie publish sensitive data findings to Security Hub CSPM

By default Macie publishes only new and updated **policy** findings to Security Hub CSPM. Provider 6.73.0 has no resource for Macie's publication settings, so use the CLI:

```bash
aws macie2 put-findings-publication-configuration \
  --security-hub-configuration publishPolicyFindings=true,publishClassificationFindings=true
aws macie2 get-findings-publication-configuration
```

Macie does not send findings that existed before this setting; only new and updated ones.

### 2. Generate sample findings

```bash
DET=$(terraform output -raw detector_id)
aws guardduty create-sample-findings --detector-id "$DET" \
  --finding-types "Backdoor:EC2/C&CActivity.B!DNS" "Recon:EC2/PortProbeUnprotectedPort" "Trojan:EC2/DNSDataExfiltration"

aws macie2 create-sample-findings
```

Sample findings are clearly marked as samples. The function never tries to isolate an instance for a sample finding.

### 3. Watch them flow

```bash
# Native GuardDuty Finding / Macie Finding events, then the Security Hub CSPM copies (ASFF)
aws logs tail "$(terraform output -raw responder_log_group)" --since 30m --follow

# The same findings in Security Hub CSPM
aws securityhub get-findings \
  --filters '{"ProductName":[{"Value":"GuardDuty","Comparison":"EQUALS"},{"Value":"Macie","Comparison":"EQUALS"}]}' \
  --query "Findings[].[ProductName,Types[0],Severity.Label,Workflow.Status]" --output table
```

GuardDuty findings usually reach Security Hub CSPM within five minutes. The Macie job takes a while to run; check it with `aws macie2 describe-classification-job --job-id "$(terraform output -raw macie_job_id)"`.

### 4. (Optional) Try isolation in a sandbox VPC

Set `isolation_vpc_id` to a sandbox VPC and `enable_isolation = true`, apply, and launch a throwaway instance there. A real (non-sample) GuardDuty EC2 finding at or above `isolation_min_severity` makes the function replace all of the instance's security groups with the isolation group, as in GuardDuty's remediation guidance. **Existing tracked connections are not terminated by a security group change**; only future traffic is blocked. To cut a live session, add a network ACL deny for the remote address on the instance's subnet.

### 5. (Optional) Delegated administrator

Only from an Organizations management account: set `delegated_admin_account_id` to your security tooling account. AWS recommends not using the management account itself and using the same delegated administrator for all security services. GuardDuty requires the same delegated admin in every Region; Security Hub CSPM is per Region unless you use central configuration. Auto-enable for member accounts is then configured from the delegated admin account (for example `aws_guardduty_organization_configuration`, `aws_macie2_organization_configuration`, `aws_securityhub_organization_configuration`), which this lab does not create.

## Honest limits

- **Macie publication settings**: no Terraform resource in provider 6.73.0; use the CLI step above.
- **Macie jobs cannot be deleted**: Macie only lets you cancel a job, so the job record can stay listed after `terraform destroy`.
- **AWS Config**: not created here; Security Hub CSPM controls need it.
- **Only one Region**: everything here is Regional. Real deployments enable all three services in every Region they use (and Security Hub CSPM cross-Region aggregation).
- **Isolation** is a lab sketch: it handles one network interface/VPC, uses broad `ec2:DescribeInstances`, and skips sample findings. Start notify-only in production.
- **Systems Manager**: the video mentions Run Command and the AWS automated response and remediation solution as targets; this lab only wires Lambda.
- **Destroy** disables Macie and Security Hub CSPM and deletes the GuardDuty detector, which deletes their findings and settings in this account and Region.

```bash
terraform destroy
```

## Sources (docs.aws.amazon.com)

- GuardDuty foundational data sources: https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_data-sources.html
- GuardDuty and Security Hub CSPM: https://docs.aws.amazon.com/guardduty/latest/ug/securityhub-integration.html
- GuardDuty EventBridge: https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_eventbridge.html
- GuardDuty with Organizations: https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_organizations.html
- Remediating a compromised EC2 instance: https://docs.aws.amazon.com/guardduty/latest/ug/compromised-ec2.html
- What is Macie: https://docs.aws.amazon.com/macie/latest/user/what-is-macie.html
- Macie and Security Hub CSPM: https://docs.aws.amazon.com/macie/latest/user/securityhub-integration.html
- Macie with Organizations: https://docs.aws.amazon.com/macie/latest/user/macie-organizations.html
- What is Security Hub CSPM: https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub.html
- What is AWS Security Hub: https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub-v2.html
- Security Hub CSPM EventBridge event types: https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cwe-integration-types.html
- Security Hub EventBridge (Findings Imported V2): https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-v2-cwe-event-types.html
- Security Hub CSPM delegated administrator: https://docs.aws.amazon.com/securityhub/latest/userguide/designate-orgs-admin-account.html
