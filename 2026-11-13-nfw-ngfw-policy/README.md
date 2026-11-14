# AWS Network Firewall policy (NGFW lesson)

Terraform practice lab for this video: https://youtu.be/JgBgqF03Z8A

## Goals

- Create a stateful rule group and a Classic Network Firewall policy that uses strict-order evaluation
- Optionally attach that policy to a Network Firewall in a small VPC (`create_firewall = true`)

## Prerequisites

- An AWS account and credentials (`aws configure` or environment variables) plus `terraform` 1.6+
- IAM permissions for the services in this folder

## Cost warning

The policy and rule group have no hourly charge. A Network Firewall endpoint does: each endpoint is billed per hour plus traffic processed. This lab leaves `create_firewall = false` so a default apply stays cheap. Set it to true only while you need an endpoint, then destroy the lab.

## What this lab cannot provision

AWS Network Firewall's next-generation (NGFW) policy — firewall engine then IPS engine, drop-by-default firewall engine, pass-by-default IPS engine, Monitor versus Enforce, embedded rules, and managed IPS rule groups — was announced on November 10, 2026. The `aws_networkfirewall_firewall_policy` resource in AWS provider 6.73.0 still documents the Classic model only (`stateless_default_actions`, `stateful_engine_options`, `stateful_rule_group_reference`, and related arguments). There is no `policy_type`, NGFW, or IPS-engine argument to set.

This lab therefore builds a Classic policy, which the lesson says continues to work unchanged. To practice an NGFW policy itself, use the AWS console, CLI, or API until the provider documents the new type. Do not add invented Terraform arguments.

## Steps

1. Copy the example variables and edit them:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Initialize and review the plan:

   ```bash
   terraform init
   terraform plan
   ```

3. Apply only after you have read the cost warning:

   ```bash
   terraform apply
   ```

Inspect an NGFW policy in the console or CLI after the provider adds support, or create one outside Terraform for comparison:

```bash
aws network-firewall list-firewall-policies --region us-east-1
```

## Verify

```bash
terraform output
aws network-firewall describe-firewall-policy --firewall-policy-name nfw-ngfw-lab-classic-policy --region us-east-1
```

Confirm the policy uses stateless default actions and a stateful rule group reference (Classic). If the describe output later gains an NGFW or policy-type field on policies you create in the console, compare it with this Classic policy.

## Cleanup

Destroy the lab when you are finished so you are not billed for idle resources:

```bash
terraform destroy
```

Confirm in the AWS console that the VPC, profiles, and any firewall endpoints are gone.
