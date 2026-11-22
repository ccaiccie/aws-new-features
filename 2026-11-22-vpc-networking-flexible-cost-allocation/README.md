# AWS VPC Networking Flexible Cost Allocation (FCA) Practice Lab

This practice lab models a common multi-team AWS networking pattern: two internal application teams (**Team Alpha** and **Team Beta**) running workloads in separate private subnets that share a single public **NAT gateway** for outbound internet access.

Using **Networking Flexible Cost Allocation (FCA)** for Amazon VPC (generally available November 16, 2026), you can split the shared NAT gateway's `data-processing` and `data-transfer` charges in your AWS Cost and Usage Report (CUR / CUR 2.0) by subnet—without changing your routing, traffic path, or total AWS bill.

## Honest Provider Note

As of `hashicorp/aws` provider `v6.73.0` (verified with `terraform providers schema`), the Terraform AWS provider does not yet include native resources for `AWS::EC2::FcaPolicy` or `AWS::EC2::FcaPolicyAssociation`.

To avoid inventing unsupported Terraform resource types, this lab:
1. Provisions the complete VPC, subnets, internet gateway, shared public NAT gateway, and route tables with **Terraform**.
2. Provides both a ready-to-deploy **AWS CloudFormation** template ([`fca-policy-cfn.yaml`](fca-policy-cfn.yaml)) using `AWS::EC2::FcaPolicy` and `AWS::EC2::FcaPolicyAssociation` and exact **AWS CLI** commands using [`nat-fca-policy.json`](nat-fca-policy.json) to create and associate the FCA policy.

## Prerequisites

- **Terraform** `>= 1.6.0`
- **AWS CLI v2** (updated to a release supporting EC2 Networking FCA commands) configured with credentials
- An AWS account in an **FCA-supported Region** (all commercial Regions except Middle East (Bahrain) and Middle East (UAE), plus China Regions; not supported in AWS GovCloud (US))
- IAM permissions for VPC/EC2 networking plus FCA policy actions (`ec2:CreateNetworkingFlexCostAllocationPolicy`, `ec2:AssociateNetworkingFlexCostAllocationPolicy`, `ec2:DescribeNetworkingFlexCostAllocationPolicies`, `ec2:DescribeNatGateways`)
- Access to **AWS Billing and Cost Management** (management account or standalone account) to enable **Networking flexible cost allocation** under split cost allocation data and configure CUR / CUR 2.0 in AWS Data Exports

## What This Lab Builds

| Resource | Purpose |
| --- | --- |
| `aws_vpc.main` (`10.20.0.0/16`) | Shared egress VPC |
| `aws_internet_gateway.main` | Outbound internet connectivity |
| `aws_subnet.public` (`10.20.0.0/24`) | Public subnet hosting the shared NAT gateway |
| `aws_subnet.team_alpha` (`10.20.10.0/24`) | Private subnet tagged `Team = alpha`, `CostCenter = cc-alpha-101` |
| `aws_subnet.team_beta` (`10.20.20.0/24`) | Private subnet tagged `Team = beta`, `CostCenter = cc-beta-202` |
| `aws_eip.nat` + `aws_nat_gateway.shared` | Single public NAT gateway shared by both private subnets |
| `aws_route_table.public` & `aws_route_table.private` | Routes public subnet `0.0.0.0/0` to IGW and both private subnets `0.0.0.0/0` to the shared NAT gateway |
| `nat-fca-policy.json` | Example `NatFcaPolicyDocument` (`ReportingGranularity: ["subnet"]`, `Dimensions: ["data-transfer", "data-processing"]`) |
| `fca-policy-cfn.yaml` | CloudFormation template creating `AWS::EC2::FcaPolicy` and `AWS::EC2::FcaPolicyAssociation` for the NAT gateway |

## Step 1: Deploy the Network with Terraform

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

Capture the NAT gateway ID from Terraform outputs:

```bash
NAT_GW_ID=$(terraform output -raw nat_gateway_id)
echo "$NAT_GW_ID"
```

## Step 2: Create and Associate the FCA Policy

Choose **either** CloudFormation (Option A) or the AWS CLI (Option B).

### Option A: CloudFormation (`AWS::EC2::FcaPolicy` + `AWS::EC2::FcaPolicyAssociation`)

```bash
aws cloudformation deploy \
  --stack-name vpc-fca-lab-policy \
  --template-file fca-policy-cfn.yaml \
  --parameter-overrides NatGatewayId="$NAT_GW_ID"
```

### Option B: AWS CLI

1. Create the NAT gateway FCA policy using [`nat-fca-policy.json`](nat-fca-policy.json):

```bash
FCA_POLICY_ID=$(aws ec2 create-networking-flex-cost-allocation-policy \
  --network-resource-type natgw \
  --nat-fca-policy-document file://nat-fca-policy.json \
  --show-back-enabled \
  --query 'FcaPolicy.FcaPolicyId' \
  --output text)

echo "$FCA_POLICY_ID"
```

2. Associate the policy with the shared NAT gateway:

```bash
aws ec2 associate-networking-flex-cost-allocation-policy \
  --fca-policy-id "$FCA_POLICY_ID" \
  --network-resource-ids "$NAT_GW_ID"
```

## Step 3: Enable Split Cost Allocation Data in Billing and Cost Management

1. Open **AWS Billing and Cost Management** in your management (or standalone) account.
2. Go to **Cost Management preferences** and turn on **Networking flexible cost allocation** under **Split cost allocation data**.
3. Confirm your **Cost and Usage Report (CUR)** or **CUR 2.0** export (in AWS Data Exports) is configured to include **split cost allocation data** and **resource IDs**.

## Step 4: Verify Configuration and Timing

1. Verify your FCA policy exists and is active:

```bash
aws ec2 describe-networking-flex-cost-allocation-policies
```

2. Verify the CloudFormation stack outputs (if you used Option A):

```bash
aws cloudformation describe-stacks \
  --stack-name vpc-fca-lab-policy \
  --query 'Stacks[0].Outputs'
```

3. **Important Timing and Billing Reminders:**
   - **Allocation is not immediate.** The expected effective time is the time you create the association **plus 60 minutes, rounded up to the next hour** (for example, an association created at 2:01 PM has an expected effective time of 4:00 PM; processing delays can make it take effect later).
   - **No historical splits.** FCA does **not** apply retroactively to usage metered before the association takes effect. Your CUR will never split historical traffic from before the effective time.
   - **CUR visibility window.** Once active and traffic flows after the effective time, allocated line items appear in CUR / CUR 2.0 **within 24 hours**, alongside the primary NAT gateway summary line item.
   - **No change to routing or total bill.** The account owning the NAT gateway still pays AWS the exact same total charge; CUR simply itemizes how much `data-processing` and `data-transfer` each subnet drove.

## Cost Notes

- **Networking Flexible Cost Allocation (FCA):** **No additional charge.**
- **AWS NAT Gateway:** Incurs standard hourly charges and per-GB data processing and data transfer charges while deployed. Destroy the lab promptly when finished testing to avoid ongoing NAT gateway hourly charges.

## Step 5: Cleanup

1. Delete the CloudFormation FCA stack (if you used Option A), or disassociate and delete the FCA policy via the VPC console / AWS CLI (if you used Option B):

```bash
aws cloudformation delete-stack --stack-name vpc-fca-lab-policy
aws cloudformation wait stack-delete-complete --stack-name vpc-fca-lab-policy
```

2. Destroy the Terraform-managed VPC and NAT gateway:

```bash
terraform destroy
```

## Official References

- [AWS What's New: Networking Flexible Cost Allocation for Amazon VPC (Nov 16, 2026)](https://aws.amazon.com/about-aws/whats-new/2026/11/networking-flexible-cost-allocation/)
- [Amazon VPC User Guide: Networking Flexible Cost Allocation](https://docs.aws.amazon.com/vpc/latest/userguide/networking-flexible-cost-allocation.html)
