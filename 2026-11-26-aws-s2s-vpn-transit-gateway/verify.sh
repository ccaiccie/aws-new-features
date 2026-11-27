#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-us-east-1}"
VPN_ID=$(terraform output -raw vpn_connection_id)
TGW_ID=$(terraform output -raw transit_gateway_id)
TGW_RT_ID=$(terraform output -raw transit_gateway_route_table_id)

echo "=== 1. VPN Connection & Tunnel Options ==="
aws ec2 describe-vpn-connections \
  --region "$REGION" \
  --vpn-connection-ids "$VPN_ID" \
  --query "VpnConnections[0].{Id:VpnConnectionId,State:State,TgwId:TransitGatewayId,Accel:Options.EnableAcceleration,StaticOnly:Options.StaticRoutesOnly,Telemetry:VgwTelemetry[*].{OutsideIp:OutsideIpAddress,Status:Status,Routes:AcceptedRouteCount}}" \
  --output json

echo "=== 2. Transit Gateway Attachments ==="
aws ec2 describe-transit-gateway-attachments \
  --region "$REGION" \
  --filters "Name=transit-gateway-id,Values=$TGW_ID" \
  --query "TransitGatewayAttachments[*].{Id:TransitGatewayAttachmentId,Type:ResourceType,State:State}" \
  --output table

echo "=== 3. Transit Gateway Route Table Entries ==="
aws ec2 search-transit-gateway-routes \
  --region "$REGION" \
  --transit-gateway-route-table-id "$TGW_RT_ID" \
  --filters "Name=state,Values=active,blackhole" \
  --query "Routes[*].{Destination:DestinationCidrBlock,Type:Type,State:State,Attachment:TransitGatewayAttachments[0].ResourceType}" \
  --output table
