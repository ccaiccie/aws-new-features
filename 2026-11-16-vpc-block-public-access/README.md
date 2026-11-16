# VPC Block Public Access (BPA): account guardrail plus exclusions

Terraform practice lab for the AWS New Features video "VPC Block Public Access: One Switch Against Internet Exposure" (YouTube playlist **aws new features**, Network Technician channel).

VPC Block Public Access is a Region-level, account-level control that blocks traffic through internet gateways and egress-only internet gateways no matter what route tables, security groups or network ACLs say. Exclusions exempt a single VPC or subnet.

## What it builds

| Piece | What it demonstrates |
| --- | --- |
| Three VPCs (`app`, `edge`, `outbound`), each with an internet gateway, public subnet and `0.0.0.0/0` route | Each would be internet-reachable without BPA |
| Exclusion on the `edge` **subnet**, `allow-bidirectional` | Subnet-level exception; everything else in the VPC stays blocked |
| Exclusion on the `outbound` **VPC**, `allow-egress` | Outbound allowed, inbound blocked. Egress-only exclusions apply when the account mode is bidirectional |
| `aws_vpc_block_public_access_options` (**off by default**) | The account/Region switch: `block-bidirectional` or `block-ingress` |

## Prerequisites

AWS credentials, Terraform 1.6+, provider `hashicorp/aws` 6.73.0. Permissions to create VPC resources and, if you enable the switch, `ec2:ModifyVpcBlockPublicAccessOptions` and the exclusion actions.

## Cost and safety warning

The VPCs, subnets, internet gateways and exclusions are free. **`enable_account_bpa = true` changes the whole Region of the account, not just these three VPCs.** It can take a few minutes to take effect and it can break any workload in the Region that relies on an internet gateway, NAT gateway, internet-facing load balancer, Network Firewall endpoint, public Direct Connect virtual interface or CloudFront VPC origin. Use a sandbox account. Run `terraform destroy` when you finish.

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply            # creates VPCs and exclusions; BPA stays off
```

Optional, sandbox only: set `enable_account_bpa = true` and `account_bpa_mode = "block-ingress"` (then try `"block-bidirectional"`) and apply. Check status:

```bash
aws ec2 describe-vpc-block-public-access-options --region us-east-2
aws ec2 describe-vpc-block-public-access-exclusions --region us-east-2
```

Wait for the options state to be on and the exclusions to be `active` before testing.

## Experiments

1. Apply with BPA off, then turn it on in `block-ingress` mode and compare `describe-vpc-block-public-access-options` before and after.
2. Switch to `block-bidirectional` and watch the `outbound` exclusion keep outbound access while inbound stays blocked.
3. Add a subnet exclusion for only one subnet of an internet-facing load balancer and read the docs note on why that still lets public traffic in.
4. Use Network Access Analyzer or Reachability Analyzer to see BPA as the blocking component.

Destroy the lab with `terraform destroy`; the options resource restores the account mode to off.
