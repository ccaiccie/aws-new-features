# AWS Security Hub & Security Hub CSPM — Terraform + AWS CLI Practice Lab

Intended repository path: `ccaiccie/aws-new-features/2026-11-26-aws-security-hub`

This single-Region practice lab enables **AWS Security Hub CSPM** in your own AWS account with consolidated control findings (`SECURITY_CONTROL`), subscribes to **AWS Foundational Security Best Practices (FSBP) v1.0.0**, creates a safe **automation rule** that adds a triage note to `INFORMATIONAL` findings, and deploys an **EventBridge Custom Action -> Read-Only Lambda** pipeline so you can see end-to-end finding routing without mutating production resources.

## Important Scope & Multi-Account Warning

- **Single standalone account and single Region only:** This lab does **not** configure AWS Organizations, a delegated administrator, cross-Region aggregation, or `SECURITYHUB_CSPM_POLICY` declarative policies.
- **Production Organizations warning:** Per current AWS documentation, Security Hub CSPM declarative policies replace central configuration and are **mutually exclusive** with central configuration. Attaching a declarative policy to even a single account disables central configuration across the entire organization. Never test org-level policies in a production organization without using the official AWS migration/import workflow.
- **AWS Config prerequisite:** Security Hub CSPM requires AWS Config resource recording in the lab Region to evaluate controls and calculate security scores. Remember to review AWS Config costs alongside Security Hub costs.
- **Never commit secrets, `.terraform/`, `*.tfstate`, or real account IDs** to version control.

## Official AWS Documentation Sources

- What are Security Hub and Security Hub CSPM?: https://docs.aws.amazon.com/securityhub/latest/userguide/what-are-securityhub-services.html
- Introduction to AWS Security Hub (unified experience): https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub-v2.html
- Enabling Security Hub CSPM: https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-settingup.html
- Managing accounts with declarative policies in Security Hub CSPM: https://docs.aws.amazon.com/securityhub/latest/userguide/accounts-orgs-policies.html
- Standards reference: https://docs.aws.amazon.com/securityhub/latest/userguide/standards-reference.html
- Calculating security scores: https://docs.aws.amazon.com/securityhub/latest/userguide/standards-security-score.html
- Finding format (ASFF): https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-findings-format.html
- Finding format (OCSF): https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-ocsf.html
- Cross-Region aggregation (Security Hub CSPM): https://docs.aws.amazon.com/securityhub/latest/userguide/finding-aggregation.html
- Cross-Region aggregation (Security Hub): https://docs.aws.amazon.com/securityhub/latest/userguide/security-hub-region-aggregation.html
- Automation rules: https://docs.aws.amazon.com/securityhub/latest/userguide/automation-rules.html
- Insights: https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-insights.html
- EventBridge & Custom Actions: https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cloudwatch-events.html
- Official Pricing: https://aws.amazon.com/security-hub/pricing/

## Deploy the Lab

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Initialize and inspect the execution plan:
   ```bash
   terraform init
   terraform plan
   ```
3. Apply the configuration in your sandbox account:
   ```bash
   terraform apply
   ```

## Verify with AWS CLI

Run the commands in `cli-walkthrough.sh` (or individually):

```bash
aws securityhub describe-hub --region us-east-1
aws securityhub get-enabled-standards --region us-east-1
aws securityhub get-findings --region us-east-1 --max-items 5
aws securityhub describe-action-targets --region us-east-1
aws securityhub list-automation-rules --region us-east-1
```

To test the custom action pipeline:
1. Open the AWS Security Hub CSPM console in `us-east-1`.
2. Select one finding on the **Findings** page.
3. Choose **Actions -> Send to Lab Triage**.
4. Inspect the CloudWatch Log Group `/aws/lambda/sechub-lab-triage-handler` to verify the EventBridge-to-Lambda JSON triage summary.

## Teardown & Cost Cleanup

Stop all recurring charges immediately when finished:

```bash
terraform destroy
```

Verify that Security Hub CSPM is disabled in the lab Region:

```bash
aws securityhub describe-hub --region us-east-1
```

Expected output: `InvalidAccessException` indicating the account is not subscribed to AWS Security Hub in that Region. If you enabled AWS Config solely for this lab, stop the Config recorder as well to prevent ongoing Config charges.
