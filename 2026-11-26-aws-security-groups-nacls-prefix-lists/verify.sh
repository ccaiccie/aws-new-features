#!/usr/bin/env bash
set -euo pipefail

# Helper script to inspect the deployed packet-filter lab with AWS CLI
REGION="${1:-us-east-1}"
PL_ID="$(terraform output -raw prefix_list_id)"
WEB_SG="$(terraform output -raw web_security_group_id)"
APP_SG="$(terraform output -raw app_security_group_id)"
PUB_NACL="$(terraform output -raw public_nacl_id)"
PRIV_NACL="$(terraform output -raw private_nacl_id)"
WEB_IP="$(terraform output -raw web_public_ip)"
APP_IP="$(terraform output -raw app_private_ip)"
LOG_GROUP="$(terraform output -raw flow_log_group_name)"

echo "=== 1. Customer-Managed Prefix List Entries ==="
aws ec2 get-managed-prefix-list-entries \
  --region "$REGION" \
  --prefix-list-id "$PL_ID" \
  --output table

echo "=== 2. Security Groups (Web & App) ==="
aws ec2 describe-security-groups \
  --region "$REGION" \
  --group-ids "$WEB_SG" "$APP_SG" \
  --query "SecurityGroups[].{Name:GroupName,Id:GroupId,In:IpPermissions,Out:IpPermissionsEgress}" \
  --output json

echo "=== 3. Network ACLs (Public & Private) ==="
aws ec2 describe-network-acls \
  --region "$REGION" \
  --network-acl-ids "$PUB_NACL" "$PRIV_NACL" \
  --query "NetworkAcls[].{Id:NetworkAclId,Entries:Entries[].{Rule:RuleNumber,Egress:Egress,Action:RuleAction,Proto:Protocol,Cidr:CidrBlock,Ports:PortRange}}" \
  --output table

echo "=== 4. HTTP Allow Test (curl Web Tier :80) ==="
curl -sS --max-time 5 "http://${WEB_IP}/" || echo "Request blocked or timed out"

echo "=== 5. Recent VPC Flow Log Events (if enabled) ==="
if [[ -n "$LOG_GROUP" ]]; then
  aws logs filter-log-events \
    --region "$REGION" \
    --log-group-name "$LOG_GROUP" \
    --limit 20 \
    --query "events[].message" \
    --output text
fi

echo "=== Done. App private IP for SSH -> curl test from web instance: http://${APP_IP}:8080 ==="
