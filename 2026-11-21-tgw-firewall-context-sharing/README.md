# AWS Transit Gateway Firewall Context Sharing & Network Firewall Context-Aware Rules Lab

This Terraform practice lab accompanies the **Network Technician** video lesson on **AWS Transit Gateway resource context sharing with firewalls** (announced November 17, 2026) and **AWS Network Firewall context-aware rules** (announced November 16, 2026).

## What This Lab Provisions

- **Two VPCs**:
  - `dev` VPC (`10.10.0.0/16`) with two private subnets and a `dev-app` security group
  - `prod` VPC (`10.20.0.0/16`) with `web` and `database` subnets plus `prod-web-sg` and `prod-db-sg` security groups
- **AWS Transit Gateway**:
  - Transit Gateway with VPC attachments for both `dev` and `prod`
- **AWS Network Manager**:
  - Global network and Transit Gateway registration (the foundation required before associating a Transit Gateway with a Network Manager Context Store)
- **AWS Network Firewall (Transit Gateway-attached)**:
  - Transit Gateway-attached Network Firewall (`transit_gateway_id` + `availability_zone_mapping`)
  - Strict-order Firewall Policy
  - Stateful Rule Group with baseline Dev-to-Prod segmentation rules

## Terraform AWS Provider Gaps (Honest Status)

Because AWS Transit Gateway context sharing and AWS Network Firewall context-aware rules were announced on **November 16–17, 2026**, the following newly introduced AWS APIs are **not yet exposed as native Terraform `hashicorp/aws` provider resources/arguments** at the time of this lab:

1. **AWS Network Manager Context Store & Transit Gateway Association**:
   - No native `aws_networkmanager_context_store` or context store association resource exists yet in the Terraform AWS provider.
   - After `terraform apply`, create the Context Store in **AWS Network Manager** (Console or AWS CLI) and associate the provisioned `transit_gateway_id` with it.
2. **AWS Network Firewall `ContextSets` on Stateful Rule Groups**:
   - The `rule_variables` block in `aws_networkfirewall_rule_group` currently supports `ip_sets` and `port_sets`, and does not yet expose `context_sets` for referencing VPC, subnet, security group, or Transit Gateway attachment IDs directly in Terraform HCL.
   - Once your Transit Gateway is associated with the Context Store, update the rule group in the AWS Network Firewall console (or AWS CLI) to replace IP sets with **Context Sets** referencing the outputs of this lab (`dev_vpc_id`, `prod_vpc_id`, `prod_web_sg_id`, `prod_db_sg_id`, `dev_tgw_attachment_id`, `prod_tgw_attachment_id`).

## Usage

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

Remember to run `terraform destroy` when you finish testing to avoid ongoing AWS Transit Gateway and AWS Network Firewall hourly charges.

## Links

- Courses: https://learn.techtohire.com
- Free Daily Quiz: https://quiz.techtohire.com
- Website: https://www.techtohire.com
