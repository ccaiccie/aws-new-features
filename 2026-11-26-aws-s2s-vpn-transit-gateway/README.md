# AWS Site-to-Site VPN with Transit Gateway — Practice Lab

Hands-on Terraform and AWS CLI lab accompanying the Network Technician lesson on **AWS Site-to-Site VPN with Transit Gateway** (high availability, inside/outside IP addressing, BGP vs. static routing, ECMP, and Accelerated VPN).

> **COST WARNING:** AWS Transit Gateway attachments, AWS Site-to-Site VPN connections, and any Accelerated Site-to-Site VPN / AWS Global Accelerator components **bill hourly (plus data transfer) until they are deleted**. Run `terraform destroy` immediately after finishing the lab and verify zero remaining resources in the AWS CLI.

## Official AWS Documentation Sources
- AWS Site-to-Site VPN Overview: https://docs.aws.amazon.com/vpn/latest/s2svpn/VPC_VPN.html
- Accelerated AWS Site-to-Site VPN Connections: https://docs.aws.amazon.com/vpn/latest/s2svpn/accelerated-vpn.html (redirected from https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-accelerated.html)
- How AWS Site-to-Site VPN Works: https://docs.aws.amazon.com/vpn/latest/s2svpn/how_it_works.html
- VPN Tunnel Options & Large Bandwidth Tunnels: https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNTunnels.html
- Configure Tunnel Options: https://docs.aws.amazon.com/vpn/latest/s2svpn/tunnel-configure.html
- Static and Dynamic Routing: https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-static-dynamic.html
- Route Tables and Route Priority: https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-route-priority.html
- Site-to-Site VPN Quotas: https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html
- AWS Transit Gateway VPN Attachments: https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpn-attachments.html
- AWS Transit Gateway Route Tables: https://docs.aws.amazon.com/vpc/latest/tgw/tgw-route-tables.html
- AWS Transit Gateway Quotas: https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html
- Create a TGW VPN Connection via CLI/API: https://docs.aws.amazon.com/vpn/latest/s2svpn/create-tgw-cli-api.html

## What This Lab Deploys
1. **AWS Transit Gateway** with `vpn_ecmp_support = "enable"`, default route table association, and default route table propagation.
2. **Two Spoke VPCs** (`10.10.0.0/16` and `10.20.0.0/16`), each with a dedicated `/28` Transit Gateway attachment subnet (per AWS Transit Gateway best practices) and a VPC route pointing the simulated on-premises CIDR (`192.168.100.0/24`) to the Transit Gateway.
3. **Simulated Customer Gateway** (`aws_customer_gateway`) using a configurable public IPv4 address (`203.0.113.10` placeholder by default — replace with your disposable test router or secondary gateway IP if bringing tunnels `UP`).
4. **Site-to-Site VPN Connection attached to the Transit Gateway** with:
   - Two redundant IPsec (`ipsec.1`) IKEv2 tunnels in separate Availability Zones.
   - Explicit inside tunnel `/30` CIDRs (`169.254.10.0/30` and `169.254.20.0/30`), avoiding AWS reserved blocks (`169.254.0.0/30`–`169.254.5.0/30` and `169.254.169.252/30`).
   - Configurable routing mode (`static_routes_only = false` for BGP + ECMP by default, or `true` for static routing with an automatic TGW static route).
   - Configurable acceleration toggle (`enable_acceleration = false` by default so you do not incur Global Accelerator charges unless you explicitly opt in).

## Prerequisites
- AWS account with permissions for EC2/VPC, Transit Gateway, and Site-to-Site VPN.
- [Terraform](https://developer.hashicorp.com/terraform/downloads) `>= 1.5.0`
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured (`aws configure`).

## Step 1: Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
```
Edit `terraform.tfvars` if you want to test:
- `static_routes_only = true` (static routing mode — note ECMP is not supported with static routing).
- `enable_acceleration = true` (Accelerated VPN — AWS creates and manages two Global Accelerators, one per tunnel, adding Global Accelerator hourly and data transfer billing; cannot be toggled on an existing VPN connection without recreating it).

## Step 2: Deploy with Terraform
```bash
terraform init
terraform plan
terraform apply
```
Inspect the outputs:
```bash
terraform output
```
You will see both tunnels' **outside public IPv4 addresses**, **inside `/30` CIDRs**, the **Transit Gateway ID**, the **VPN Connection ID**, and the **Transit Gateway VPN Attachment ID**.

## Step 3: AWS CLI Walkthrough (Alternative / Verification)
You can also create a Transit Gateway Site-to-Site VPN directly with the AWS CLI:
```bash
aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --transit-gateway-id <tgw-id> \
  --customer-gateway-id <cgw-id> \
  --options "StaticRoutesOnly=false,EnableAcceleration=false,TunnelOptions=[{TunnelInsideCidr=169.254.10.0/30,StartupAction=add},{TunnelInsideCidr=169.254.20.0/30,StartupAction=add}]"
```

Run the verification script to check VPN state, tunnel telemetry, TGW attachments, and TGW route table entries:
- Linux / macOS: `./verify.sh us-east-1`
- Windows PowerShell: `.\verify.ps1 -Region us-east-1`

> Note: With a simulated documentation IP (`203.0.113.10`), the VPN connection reaches `available` while both tunnels remain `DOWN` until a real or disposable customer gateway device initiates IKEv2 (UDP 500 / UDP 4500 for NAT-T) and establishes the BGP session on the inside `.1`/`.2` addresses.

## Step 4: Teardown & Cost Cleanup (Required!)
Destroy all lab resources immediately when finished so Transit Gateway attachments, Site-to-Site VPN connections, and any AWS-managed Global Accelerators stop billing:
```bash
terraform destroy -auto-approve
```

Verify nothing remains in your AWS Region:
```bash
aws ec2 describe-vpn-connections --region us-east-1 \
  --filters "Name=tag:Name,Values=tgw-s2s-vpn-lab-tgw-vpn" \
  --query "VpnConnections[*].{Id:VpnConnectionId,State:State}"

aws ec2 describe-transit-gateways --region us-east-1 \
  --filters "Name=tag:Name,Values=tgw-s2s-vpn-lab-tgw" \
  --query "TransitGateways[*].{Id:TransitGatewayId,State:State}"
```
Confirm both return empty lists (or `deleted`) before closing your terminal.
