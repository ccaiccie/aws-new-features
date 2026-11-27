# Amazon VPC Packet-Filter Design Lab: Security Groups, Network ACLs, and Managed Prefix Lists

Practice lab for the Network Technician class on **Security Groups, Network ACLs, and Managed Prefix Lists** in Amazon VPC.

Intended repository path:
`https://github.com/ccaiccie/aws-new-features/tree/main/2026-11-26-aws-security-groups-nacls-prefix-lists`

> **COST WARNING:** Security groups, network ACLs, and sharing customer-managed prefix lists carry no additional charge, **however** the EC2 compute instances (`t3.micro`), the public IPv4 address attached to the web instance, and VPC Flow Logs ingestion/storage in CloudWatch Logs **bill until they are deleted**. This lab deliberately **avoids NAT gateways and VPC endpoints** (using Python's built-in HTTP server on Amazon Linux 2023) to minimize cost. Always run `terraform destroy` as soon as you finish testing.

## Official AWS Documentation Sources
- Security groups: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html
- Security group rules: https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html
- Network ACLs: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- Custom network ACLs & ephemeral ports: https://docs.aws.amazon.com/vpc/latest/userguide/custom-network-acl.html
- Compare security groups and network ACLs: https://docs.aws.amazon.com/vpc/latest/userguide/infrastructure-security.html#VPC_Security_Comparison
- Managed prefix lists: https://docs.aws.amazon.com/vpc/latest/userguide/managed-prefix-lists.html
- Referencing managed prefix lists: https://docs.aws.amazon.com/vpc/latest/userguide/managed-prefix-lists-referencing.html
- Sharing customer-managed prefix lists (AWS RAM): https://docs.aws.amazon.com/vpc/latest/userguide/sharing-managed-prefix-lists.html
- Amazon VPC quotas: https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html
- VPC Flow Logs: https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html

## Architecture Overview
- **VPC**: `10.20.0.0/16` with an Internet Gateway (`igw-packet-filter-lab`) and **no NAT gateway**.
- **Public Web Subnet (`10.20.1.0/24`)**:
  - Custom stateless NACL (`nacl-public-web`) allowing inbound TCP 80/22, inbound ephemeral TCP `1024-65535` from `10.20.2.0/24`, outbound TCP 8080 to `10.20.2.0/24`, and toggleable outbound ephemeral TCP `1024-65535` to `0.0.0.0/0` (plus an optional lower-numbered explicit DENY rule `90`).
  - Stateful Security Group (`sg-web-tier`) allowing inbound TCP 80 and TCP 22 **only** from the customer-managed prefix list (`pl-trusted-admin-ranges`, `max_entries = 5`) and outbound TCP 8080 **only** to `sg-app-tier`.
  - EC2 instance (`ec2-public-web`, `t3.micro`) running `python3 -m http.server 80`.
- **Private App Subnet (`10.20.2.0/24`)**:
  - Custom stateless NACL (`nacl-private-app`) allowing inbound TCP 8080 from `10.20.1.0/24` and outbound ephemeral TCP `1024-65535` to `10.20.1.0/24`.
  - Stateful Security Group (`sg-app-tier`) allowing inbound TCP 8080 **only** from `sg-web-tier` (SG-to-SG reference) and **zero outbound rules**—proving stateful return traffic still succeeds automatically.
  - EC2 instance (`ec2-private-app`, `t3.micro`) running `python3 -m http.server 8080`.
- **VPC Flow Logs**: Enabled on the VPC (`traffic_type = "ALL"`) into CloudWatch Logs (1-day retention) to observe `ACCEPT` and `REJECT` records.

## Prerequisites
- Terraform `>= 1.5.0`
- AWS CLI v2 configured with credentials for your lab account
- `curl`

## 1. Configure and Deploy
```bash
cp terraform.tfvars.example terraform.tfvars
```
Edit `terraform.tfvars` and replace `203.0.113.10/32` with your own public IPv4 address (`/32`), e.g. from `curl -s https://checkip.amazonaws.com`.

```bash
terraform init
terraform plan
terraform apply
```

## 2. Verify Allow, Deny, Stateless Ephemeral Ports, and Flow Logs

### A. Inspect with AWS CLI and curl (Allowed Baseline)
```bash
bash verify.sh us-east-1
```
Or run individual commands:
```bash
WEB_IP=$(terraform output -raw web_public_ip)
curl -i --max-time 5 "http://${WEB_IP}/"
```
Expected result: `200 OK` with `WEB-TIER OK (port 80) - Stateful SG + Stateless NACL passed`.

If you configured `key_name`, SSH to `ec2-public-web` and curl the private app instance:
```bash
ssh ec2-user@${WEB_IP}
curl -i --max-time 5 "http://<app_private_ip>:8080/"
```
Expected result: `200 OK` even though `sg-app-tier` has **no outbound rules** (proving stateful SG return traffic).

### B. Prove Stateless NACL Ephemeral-Port Requirement
Disable outbound ephemeral ports on `nacl-public-web`:
```bash
terraform apply -var="enable_ephemeral_outbound_nacl=false"
curl -i --max-time 5 "http://${WEB_IP}/"
```
Expected result: **Connection times out!** The inbound SYN reaches the web server, but the stateless NACL's `*` DENY blocks the outbound SYN-ACK on ephemeral ports. Restore it:
```bash
terraform apply -var="enable_ephemeral_outbound_nacl=true"
```

### C. Prove Explicit NACL DENY (Rule 90 Before Rule 100)
Block your own `/32` IP at rule 90 (lower than rule 100 ALLOW):
```bash
terraform apply -var="block_test_cidr=<YOUR_PUBLIC_IP>/32"
curl -i --max-time 5 "http://${WEB_IP}/"
```
Expected result: **Connection times out!** Rule 90 matches first and denies before rule 100 is evaluated. Remove the deny rule:
```bash
terraform apply -var="block_test_cidr="
```

### D. Verify VPC Flow Logs (`ACCEPT` and `REJECT`)
Wait ~1–5 minutes for Nitro aggregation and CloudWatch Logs delivery, then query:
```bash
LOG_GROUP=$(terraform output -raw flow_log_group_name)
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "REJECT" \
  --limit 10 \
  --query "events[].message" \
  --output text
```
And for accepted flows:
```bash
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "ACCEPT" \
  --limit 10 \
  --query "events[].message" \
  --output text
```

## 3. Teardown and Cleanup (Stop All Billing)
Destroy every lab resource immediately when done:
```bash
terraform destroy
```
Verify nothing remains billed in the Region:
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=vpc-packet-filter-lab" "Name=instance-state-name,Values=running,pending,stopped" \
  --query "Reservations[].Instances[].InstanceId"

aws ec2 describe-managed-prefix-lists \
  --filters "Name=prefix-list-name,Values=pl-trusted-admin-ranges" \
  --query "PrefixLists[].PrefixListId"
```
Both commands should return an empty list `[]`.
