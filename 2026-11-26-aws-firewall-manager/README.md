# AWS Firewall Manager Practice Lab (Terraform + AWS CLI)

Hands-on practice lab for the Network Technician lesson on **AWS Firewall Manager** (org-wide WAF, Shield, security group, and Network Firewall policies).

Intended repository path: `ccaiccie/aws-new-features/2026-11-26-aws-firewall-manager`

## Official AWS Sources

- AWS Firewall Manager overview: https://docs.aws.amazon.com/waf/latest/developerguide/fms-chapter.html
- AWS Firewall Manager prerequisites: https://docs.aws.amazon.com/waf/latest/developerguide/fms-prereq.html
- Using Firewall Manager administrators: https://docs.aws.amazon.com/waf/latest/developerguide/fms-administrators.html
- Using Firewall Manager policies: https://docs.aws.amazon.com/waf/latest/developerguide/working-with-policies.html
- Using Firewall Manager policy scope: https://docs.aws.amazon.com/waf/latest/developerguide/policy-scope.html
- Viewing compliance information: https://docs.aws.amazon.com/waf/latest/developerguide/fms-compliance.html
- Using AWS WAF policies: https://docs.aws.amazon.com/waf/latest/developerguide/waf-policies.html
- Using AWS Shield Advanced policies: https://docs.aws.amazon.com/waf/latest/developerguide/shield-policies.html
- Using security group policies: https://docs.aws.amazon.com/waf/latest/developerguide/security-group-policies.html
- Using AWS Network Firewall policies: https://docs.aws.amazon.com/waf/latest/developerguide/network-firewall-policies.html

## Important Cost & Account Scope Notes

1. **AWS Organizations required:** AWS Firewall Manager requires an AWS Organization with **All features** enabled, a **default administrator account** designated by the management account, and **AWS Config** enabled with **Continuous** recording across member accounts and target Regions.
2. **Two-account lab model:** Prefer a non-production two-account Organization (management/delegated admin account + member workload account inside a dedicated lab OU). If you only have a single standalone AWS account, do not create a production Organization just to test—read the Terraform files and CLI walkthrough here as a reference until you have a sandbox Organization.
3. **No paid Shield Advanced subscription:** This lab intentionally does **not** subscribe to AWS Shield Advanced or create a Shield Advanced policy.
4. **No real production IDs or secrets:** Never commit `terraform.tfvars`, `.tfstate`, or real account IDs.

## Prerequisites Checklist

Before running Terraform from your **Firewall Manager administrator account**:

1. Enable **All features** in AWS Organizations.
2. From the Organizations management account, designate a Firewall Manager default administrator account (Firewall Manager Console -> Settings -> Create administrator account, or `aws fms associate-admin-account`).
3. Enable **AWS Config** (Continuous recording) in both the administrator account and every in-scope member account in your target Region.
4. (Optional, only if you extend this lab to Network Firewall or DNS Firewall policies) Enable **AWS RAM** resource sharing with AWS Organizations.

## Step 1: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your lab OU ID, your Firewall Manager administrator account ID in `excluded_account_ids`, and a VPC ID inside your administrator account for the primary security group. Keep `remediation_enabled = false` for your first deployment so Firewall Manager audits and flags without modifying live resources.

## Step 2: Deploy with Terraform

```bash
terraform init
terraform plan
terraform apply
```

This creates:
- A primary baseline HTTPS security group (`nt-fms-lab-primary-https-sg`) in the administrator account.
- A **Common Security Group** Firewall Manager policy (`SECURITY_GROUPS_COMMON`) scoped to your lab OU, excluding the administrator account and any resource tagged `fms-exempt = "true"`.
- An **AWS WAFv2** Firewall Manager policy (`WAFV2`) applying `AWSManagedRulesCommonRuleSet` as a first rule group for Application Load Balancers in the lab OU, with the same tag exclusion.

## Step 3: Verify with AWS CLI

Run the verification script from your Firewall Manager administrator account:

```bash
chmod +x cli-walkthrough.sh
./cli-walkthrough.sh
```

Then export the policy ID from `terraform output` and a member account ID to inspect compliance and drift:

```bash
export POLICY_ID="$(terraform output -raw common_sg_policy_id)"
export MEMBER_ACCOUNT_ID="222233334444"
./cli-walkthrough.sh
```

## Step 4: Observe Audit vs. Remediation (Optional)

1. Deploy an Application Load Balancer in the in-scope member account **without** the `fms-exempt=true` tag. Wait several minutes for AWS Config continuous recording to evaluate it and observe `Noncompliant` in `list-compliance-status`.
2. Tag a second test resource with `fms-exempt = "true"` and confirm it stays out of scope.
3. Flip `remediation_enabled = true` in `terraform.tfvars`, run `terraform apply`, and observe Firewall Manager apply the policy and transition the in-scope resource to `Compliant`.

## Step 5: Teardown & Cleanup (Stop Ongoing Charges)

Always destroy lab resources when finished:

```bash
terraform destroy
```

Because `delete_all_policy_resources_on_destroy = true` and `delete_unused_fm_managed_resources = true`, Firewall Manager cleans up the managed web ACLs and replica security groups it created.

After `terraform destroy`, verify no ongoing charges remain:
- Delete any test Application Load Balancers or EC2 instances you created in the member account.
- Confirm no leftover Firewall Manager policies remain (`aws fms list-policies`).
- If you enabled **AWS Config** solely for this lab, stop the configuration recorder in the lab accounts/Regions so AWS Config recording charges stop.
- If you no longer need the Firewall Manager administrator association in your lab Organization, disassociate it from the management account (`aws fms disassociate-admin-account`).
