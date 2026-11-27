param(
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$VpnId   = terraform output -raw vpn_connection_id
$TgwId   = terraform output -raw transit_gateway_id
$TgwRtId = terraform output -raw transit_gateway_route_table_id

Write-Host "=== 1. VPN Connection & Tunnel Telemetry ==="
aws ec2 describe-vpn-connections `
  --region $Region `
  --vpn-connection-ids $VpnId `
  --query "VpnConnections[0].{Id:VpnConnectionId,State:State,TgwId:TransitGatewayId,Accel:Options.EnableAcceleration,StaticOnly:Options.StaticRoutesOnly,Telemetry:VgwTelemetry[*].{OutsideIp:OutsideIpAddress,Status:Status,Routes:AcceptedRouteCount}}" `
  --output json

Write-Host "=== 2. Transit Gateway Attachments ==="
aws ec2 describe-transit-gateway-attachments `
  --region $Region `
  --filters "Name=transit-gateway-id,Values=$TgwId" `
  --query "TransitGatewayAttachments[*].{Id:TransitGatewayAttachmentId,Type:ResourceType,State:State}" `
  --output table

Write-Host "=== 3. Transit Gateway Route Table Entries ==="
aws ec2 search-transit-gateway-routes `
  --region $Region `
  --transit-gateway-route-table-id $TgwRtId `
  --filters "Name=state,Values=active,blackhole" `
  --query "Routes[*].{Destination:DestinationCidrBlock,Type:Type,State:State,Attachment:TransitGatewayAttachments[0].ResourceType}" `
  --output table
