#!/usr/bin/env bash
set -euo pipefail

# Run this script from the lab/ directory AFTER `terraform apply`.
# Uses your configured AWS CLI credentials and reads Terraform outputs locally.

VPC_ID=$(terraform output -raw vpc_id)
SUBNET_ID=$(terraform output -raw private_ipv6_subnet_id)
RTB_ID=$(terraform output -raw private_route_table_id)
EIGW_ID=$(terraform output -raw egress_only_igw_id)

echo "=== 1. Inspect VPC IPv6 CIDR Association ==="
aws ec2 describe-vpcs \
  --vpc-ids "$VPC_ID" \
  --query "Vpcs[0].{Cidr:CidrBlock,IPv6:Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlock}" \
  --output table

echo "=== 2. Inspect Private Subnet DNS64 & IPv6-Native Attributes ==="
aws ec2 describe-subnets \
  --subnet-ids "$SUBNET_ID" \
  --query "Subnets[0].{Ipv6Native:Ipv6Native,EnableDns64:EnableDns64,AssignIpv6:AssignIpv6AddressOnCreation}" \
  --output table

echo "=== 3. Inspect Egress-Only Internet Gateway ==="
aws ec2 describe-egress-only-internet-gateways \
  --egress-only-internet-gateway-ids "$EIGW_ID" \
  --query "EgressOnlyInternetGateways[0].Attachments" \
  --output table

echo "=== 4. Inspect Private Route Table (64:ff9b::/96 -> NAT GW, ::/0 -> EIGW) ==="
aws ec2 describe-route-tables \
  --route-table-ids "$RTB_ID" \
  --query "RouteTables[0].Routes[].{DestV6:DestinationIpv6CidrBlock,NatGw:NatGatewayId,EIGW:EgressOnlyInternetGatewayId,Gateway:GatewayId,State:State}" \
  --output table

echo "=== 5. Next: Connect via SSM Session Manager to test IPv6 and DNS64/NAT64 ==="
echo "aws ssm start-session --target \$(terraform output -raw test_instance_id)"
echo ""
echo "Inside the EC2 instance, run:"
echo "  ip -6 addr show"
echo "  curl -6 -I https://ipv6.google.com                  # Native IPv6 via EIGW"
echo "  dig +short AAAA ipv4.icanhazip.com                  # Synthesized 64:ff9b::/96 via DNS64"
echo "  curl -6 https://ipv4.icanhazip.com                  # IPv6 -> IPv4 via NAT64 (returns NAT GW EIP)"
