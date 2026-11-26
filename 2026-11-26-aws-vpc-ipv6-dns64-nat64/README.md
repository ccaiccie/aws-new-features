# AWS VPC IPv6, Egress-Only Internet Gateway, DNS64, and NAT64 Lab

Companion Terraform and AWS CLI practice lab for the **Network Technician** lesson on **IPv6 in Amazon VPC: Dual-Stack, Egress-Only Internet Gateway, DNS64, and NAT64**.

Intended repository path: `ccaiccie/aws-new-features/2026-11-26-aws-vpc-ipv6-dns64-nat64`

## What This Lab Deploys

1. **Dual-stack VPC** (`10.64.0.0/16` + Amazon-provided `/56` IPv6 GUA CIDR block, with DNS support and DNS hostnames enabled).
2. **Public Subnet** (`10.64.1.0/24` + `/64` IPv6) with an **Internet Gateway**, an **Elastic IP**, and a **public NAT Gateway** (NAT64 is automatically available on AWS NAT Gateways).
3. **Egress-Only Internet Gateway (EIGW)** attached to the VPC for stateful outbound-only IPv6 internet traffic.
4. **Private IPv6-Only Subnet** (`ipv6_native = true`, `/64` IPv6 CIDR, `enable_dns64 = true`) with a private route table containing:
   - `64:ff9b::/96` -> **NAT Gateway** (NAT64 path to IPv4 destinations)
   - `::/0` -> **Egress-Only Internet Gateway** (outbound-only IPv6 internet path)
5. **Optional Nitro EC2 Test Instance** (`t3.micro`, Amazon Linux 2023) in the private IPv6-only subnet with AWS Systems Manager Session Manager access (no inbound ports opened).

## Cost Notice

- An **Egress-Only Internet Gateway** has **no hourly charge** (standard EC2 data transfer charges apply).
- A **NAT Gateway**, **Elastic IP**, and **EC2 instance** incur hourly and data-processing charges while running. **Always run `terraform destroy` when finished** so charges stop.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI v2 configured with credentials for your own AWS account
- Session Manager plugin for the AWS CLI (optional, for connecting to the test instance)

## Step 1: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` if you want to change `aws_region` or `project_name`. Never commit `terraform.tfvars`, `.terraform/`, or `*.tfstate` files.

## Step 2: Deploy the Lab

```bash
terraform init
terraform plan
terraform apply
```

## Step 3: Verify with AWS CLI

Run the included verification script:

```bash
bash verify.sh
```

Or run the AWS CLI inspection commands individually:

```bash
# Check VPC IPv6 CIDR
aws ec2 describe-vpcs --vpc-ids $(terraform output -raw vpc_id) \
  --query "Vpcs[0].Ipv6CidrBlockAssociationSet"

# Check subnet DNS64 attribute
aws ec2 describe-subnets --subnet-ids $(terraform output -raw private_ipv6_subnet_id) \
  --query "Subnets[0].{Ipv6Native:Ipv6Native,EnableDns64:EnableDns64}"

# Check private route table entries (64:ff9b::/96 -> NAT GW and ::/0 -> EIGW)
aws ec2 describe-route-tables --route-table-ids $(terraform output -raw private_route_table_id) \
  --query "RouteTables[0].Routes"
```

### Safe Connectivity Tests on the IPv6-Only Instance

Connect using Session Manager:

```bash
aws ssm start-session --target $(terraform output -raw test_instance_id)
```

Then verify:

```bash
# 1. Confirm the instance has only an IPv6 GUA (plus IPv4 link-local 169.254.0.0/16 for VPC services)
ip -6 addr show

# 2. Native IPv6 outbound via Egress-Only Internet Gateway (::/0 -> eigw)
curl -6 -I https://ipv6.google.com

# 3. DNS64 synthesis of an IPv4-only hostname into 64:ff9b::/96
dig +short AAAA ipv4.icanhazip.com

# 4. IPv6-to-IPv4 reachability via NAT64 (returns the NAT Gateway Elastic IP)
curl -6 https://ipv4.icanhazip.com
```

## Step 4: Tear Down and Clean Up

Destroy all resources immediately after testing so NAT Gateway, Elastic IP, and EC2 charges stop:

```bash
terraform destroy
```

Confirm in the AWS Console or CLI that the NAT Gateway is deleted and the Elastic IP is released.

## Official AWS Documentation Sources

- VPC IP addressing: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-ip-addressing.html
- Egress-only internet gateway: https://docs.aws.amazon.com/vpc/latest/userguide/egress-only-internet-gateway.html
- DNS64 and NAT64: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-nat64-dns64.html
- VPC CIDR blocks: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-cidr-blocks.html
- Subnet CIDR blocks: https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html
- Understanding Amazon DNS: https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html
- Subnets for your VPC: https://docs.aws.amazon.com/vpc/latest/userguide/configure-subnets.html
