#!/usr/bin/env bash
# Turn Multipath Resilience on or off for both sides of a cross-Region connection, or show its status.
# hashicorp/aws 6.73.0 has no argument for it yet, so this uses the AWS CLI (needs a CLI version that knows
# AllowMultipathResilience; update the CLI if the option is rejected).
#
# Usage:
#   scripts/multipath.sh pcx enable|disable|status <pcx-id>         <region-a> <region-b>
#   scripts/multipath.sh tgw enable|disable|status <tgw-attach-id>  <region-a> <region-b>
# Region A = requester side, Region B = accepter side. Easiest:
#   scripts/multipath.sh pcx enable "$(terraform output -raw vpc_peering_connection_id)" \
#     "$(terraform output -raw region_a)" "$(terraform output -raw region_b)"
set -euo pipefail
kind=${1:?pcx or tgw}; action=${2:?enable, disable or status}; id=${3:?connection id}
ra=${4:?requester Region}; rb=${5:?accepter Region}
case "$action" in enable) flag=true ;; disable) flag=false ;; status) flag="" ;; *) echo "bad action" >&2; exit 2 ;; esac

status() {
  if [ "$kind" = pcx ]; then
    aws ec2 describe-vpc-peering-connections --region "$ra" --vpc-peering-connection-ids "$id" \
      --query 'VpcPeeringConnections[0].{Status:Status.Code,Multipath:MultipathResilienceStatus,Requester:RequesterVpcInfo.PeeringOptions,Accepter:AccepterVpcInfo.PeeringOptions}'
  else
    aws ec2 describe-transit-gateway-peering-attachments --region "$ra" --transit-gateway-attachment-ids "$id" \
      --query 'TransitGatewayPeeringAttachments[0].{State:State,Options:Options}'
  fi
}

if [ -n "$flag" ]; then
  if [ "$kind" = pcx ]; then
    # Each side is modified in its own Region.
    aws ec2 modify-vpc-peering-connection-options --region "$ra" --vpc-peering-connection-id "$id" \
      --requester-peering-connection-options "AllowMultipathResilience=$flag"
    aws ec2 modify-vpc-peering-connection-options --region "$rb" --vpc-peering-connection-id "$id" \
      --accepter-peering-connection-options "AllowMultipathResilience=$flag"
  elif [ "$kind" = tgw ]; then
    aws ec2 modify-transit-gateway-peering-attachment --region "$ra" --transit-gateway-attachment-id "$id" \
      --options "AllowMultipathResilience=$flag"
    aws ec2 modify-transit-gateway-peering-attachment --region "$rb" --transit-gateway-attachment-id "$id" \
      --options "AllowMultipathResilience=$flag"
  else
    echo "kind must be pcx or tgw" >&2; exit 2
  fi
  echo "Requested AllowMultipathResilience=$flag on both sides; status is 'pending' until both sides agree."
  sleep 15
fi
status
