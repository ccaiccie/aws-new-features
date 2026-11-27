#!/usr/bin/env bash
set -euo pipefail

# Cleanup script: deletes CLI-created analyses/scopes and destroys Terraform resources.
REGION="${AWS_REGION:-us-east-1}"

if [[ -n "${NAA_ANALYSIS_ID:-}" ]]; then
  echo "Deleting Network Access Scope analysis: $NAA_ANALYSIS_ID"
  aws ec2 delete-network-insights-access-scope-analysis \
    --region "$REGION" \
    --network-insights-access-scope-analysis-id "$NAA_ANALYSIS_ID" || true
fi

if [[ -n "${SCOPE_ID:-}" ]]; then
  echo "Deleting Network Access Scope: $SCOPE_ID"
  aws ec2 delete-network-insights-access-scope \
    --region "$REGION" \
    --network-insights-access-scope-id "$SCOPE_ID" || true
fi

if [[ -n "${WORK_ANALYSIS_ID:-}" ]]; then
  echo "Deleting Reachability Analyzer analysis: $WORK_ANALYSIS_ID"
  aws ec2 delete-network-insights-analysis \
    --region "$REGION" \
    --network-insights-analysis-id "$WORK_ANALYSIS_ID" || true
fi

if [[ -n "${BLOCK_ANALYSIS_ID:-}" ]]; then
  echo "Deleting Reachability Analyzer analysis: $BLOCK_ANALYSIS_ID"
  aws ec2 delete-network-insights-analysis \
    --region "$REGION" \
    --network-insights-analysis-id "$BLOCK_ANALYSIS_ID" || true
fi

rm -f scope-internet-exposure.json

echo "Destroying Terraform lab infrastructure..."
terraform destroy -auto-approve
