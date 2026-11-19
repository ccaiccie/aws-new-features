#!/usr/bin/env bash
# Manage the transit gateway network function attachment of type Gateway Load Balancer
# with the AWS CLI (hashicorp/aws 6.73.0 has no resource for it).
# Run from the lab folder after `terraform apply`. Needs a current AWS CLI v2.
#
#   scripts/nf-attachment.sh create              # one GWLB endpoint per appliance AZ
#   scripts/nf-attachment.sh accept <attach-id>  # if acceptance_required = true
#   scripts/nf-attachment.sh status <attach-id>
#   scripts/nf-attachment.sh remove-az <attach-id> <az-id>
#   scripts/nf-attachment.sh add-az <attach-id> <az-id>
#   scripts/nf-attachment.sh delete <attach-id>  # after removing routes (nf_attachment_id = "")
set -euo pipefail

out() { terraform output -raw "$1"; }
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
cmd="${1:-}"

case "$cmd" in
  create)
    TGW="$(out transit_gateway_id)"
    SVC="$(out endpoint_service_name)"
    AZIDS="$(terraform output -json appliance_az_ids | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)))')"
    echo "Transit gateway $TGW, endpoint service $SVC, AZ IDs $AZIDS"
    # Prerequisite check: encryption support must be disabled on the transit gateway.
    aws ec2 describe-transit-gateways --region "$REGION" --transit-gateway-ids "$TGW" \
      --query 'TransitGateways[0].Options' --output json
    # shellcheck disable=SC2086
    aws ec2 create-transit-gateway-network-function-attachment --region "$REGION" \
      --transit-gateway-id "$TGW" \
      --service-name "$SVC" \
      --availability-zone-ids $AZIDS
    echo "Copy the tgw-attach-... ID from the output into nf_attachment_id, then accept (if required) and terraform apply."
    ;;
  accept)
    aws ec2 accept-vpc-endpoint-connections --region "$REGION" \
      --service-id "$(out endpoint_service_id)" \
      --transit-gateway-attachment-ids "$2"
    ;;
  status)
    aws ec2 describe-transit-gateway-attachments --region "$REGION" \
      --transit-gateway-attachment-ids "$2" --output table
    ;;
  add-az)
    aws ec2 modify-transit-gateway-network-function-attachment --region "$REGION" \
      --transit-gateway-attachment-id "$2" --add-availability-zone-ids "$3"
    ;;
  remove-az)
    aws ec2 modify-transit-gateway-network-function-attachment --region "$REGION" \
      --transit-gateway-attachment-id "$2" --remove-availability-zone-ids "$3"
    ;;
  delete)
    aws ec2 delete-transit-gateway-network-function-attachment --region "$REGION" \
      --transit-gateway-attachment-id "$2"
    ;;
  *)
    sed -n '2,12p' "$0"; exit 1 ;;
esac
