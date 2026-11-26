#!/usr/bin/env bash
# AWS Firewall Manager CLI Verification Walkthrough
# Run with credentials for your Firewall Manager administrator account
# (except step 1, which can also be checked from the Organizations management account).

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

echo "=== 1. Verify AWS Organizations (must show FeatureSet: ALL) ==="
aws organizations describe-organization --query 'Organization.{Id:Id,FeatureSet:FeatureSet}' --output table

echo "=== 2. Verify Firewall Manager Default Administrator Account ==="
aws fms get-admin-account --region "$REGION"

echo "=== 3. Verify AWS Config Recorder (Continuous recording required) ==="
aws configservice describe-configuration-recorders --region "$REGION"
aws configservice describe-configuration-recorder-status --region "$REGION"

echo "=== 4. List Firewall Manager Policies ==="
aws fms list-policies --region "$REGION" --output table

# Replace POLICY_ID and MEMBER_ACCOUNT_ID with values from step 4 and your lab member account
if [[ -n "${POLICY_ID:-}" ]]; then
  echo "=== 5. Inspect Policy Details ==="
  aws fms get-policy --region "$REGION" --policy-id "$POLICY_ID"

  echo "=== 6. List Account Compliance Status ==="
  aws fms list-compliance-status --region "$REGION" --policy-id "$POLICY_ID" --output table

  if [[ -n "${MEMBER_ACCOUNT_ID:-}" ]]; then
    echo "=== 7. Get Per-Account Compliance Detail ==="
    aws fms get-compliance-detail \
      --region "$REGION" \
      --policy-id "$POLICY_ID" \
      --member-account "$MEMBER_ACCOUNT_ID"
  fi
else
  echo "Tip: Export POLICY_ID and MEMBER_ACCOUNT_ID, then re-run to inspect compliance and drift."
fi
