#!/usr/bin/env bash
set -euo pipefail

# Cost warning:
# Running Reachability Analyzer analyses and Network Access Analyzer analyses incurs AWS charges.
# Delete all resources and run 'terraform destroy' when finished.

REGION="${AWS_REGION:-us-east-1}"
VPC_ID="$(terraform output -raw vpc_id)"
WORKING_PATH_ID="$(terraform output -raw working_path_id)"
BLOCKED_PATH_ID="$(terraform output -raw blocked_path_id)"

echo "=== 1. Start Reachability Analyzer on working path (web -> app TCP 443) ==="
WORK_ANALYSIS_ID="$(aws ec2 start-network-insights-analysis \
  --region "$REGION" \
  --network-insights-path-id "$WORKING_PATH_ID" \
  --query 'NetworkInsightsAnalysis.NetworkInsightsAnalysisId' \
  --output text)"
echo "Started working analysis: $WORK_ANALYSIS_ID"

echo "=== 2. Start Reachability Analyzer on blocked path (app -> db TCP 5432) ==="
BLOCK_ANALYSIS_ID="$(aws ec2 start-network-insights-analysis \
  --region "$REGION" \
  --network-insights-path-id "$BLOCKED_PATH_ID" \
  --query 'NetworkInsightsAnalysis.NetworkInsightsAnalysisId' \
  --output text)"
echo "Started blocked analysis: $BLOCK_ANALYSIS_ID"

echo "=== 3. Wait for Reachability Analyzer results ==="
for AID in "$WORK_ANALYSIS_ID" "$BLOCK_ANALYSIS_ID"; do
  while true; do
    STATUS="$(aws ec2 describe-network-insights-analyses \
      --region "$REGION" \
      --network-insights-analysis-ids "$AID" \
      --query 'NetworkInsightsAnalyses[0].Status' \
      --output text)"
    echo "Analysis $AID status: $STATUS"
    if [[ "$STATUS" != "running" ]]; then
      break
    fi
    sleep 5
  done
done

echo "=== Working Path Result ==="
aws ec2 describe-network-insights-analyses \
  --region "$REGION" \
  --network-insights-analysis-ids "$WORK_ANALYSIS_ID" \
  --query 'NetworkInsightsAnalyses[0].{PathFound:NetworkPathFound,Hops:ForwardPathComponents[*].{Seq:SequenceNumber,Id:Component.Id,Name:Component.Name}}' \
  --output table

echo "=== Blocked Path Result ==="
aws ec2 describe-network-insights-analyses \
  --region "$REGION" \
  --network-insights-analysis-ids "$BLOCK_ANALYSIS_ID" \
  --query 'NetworkInsightsAnalyses[0].{PathFound:NetworkPathFound,Explanations:Explanations[*].{Code:ExplanationCode,Direction:Direction,Port:Port}}' \
  --output json

echo "=== 4. Create Network Access Analyzer Scope (unexpected non-443 internet access) ==="
cat > scope-internet-exposure.json <<EOF
{
  "MatchPaths": [
    {
      "Source": {
        "ResourceStatement": {
          "ResourceTypes": ["AWS::EC2::InternetGateway"]
        }
      },
      "Destination": {
        "ResourceStatement": {
          "Resources": ["${VPC_ID}"]
        }
      }
    }
  ],
  "ExcludePaths": [
    {
      "Destination": {
        "PacketHeaderStatement": {
          "DestinationPorts": ["443"]
        }
      }
    }
  ]
}
EOF

SCOPE_ID="$(aws ec2 create-network-insights-access-scope \
  --region "$REGION" \
  --cli-input-json file://scope-internet-exposure.json \
  --query 'NetworkInsightsAccessScope.NetworkInsightsAccessScopeId' \
  --output text)"
echo "Created Network Access Scope: $SCOPE_ID"

echo "=== 5. Start Network Access Scope Analysis ==="
NAA_ANALYSIS_ID="$(aws ec2 start-network-insights-access-scope-analysis \
  --region "$REGION" \
  --network-insights-access-scope-id "$SCOPE_ID" \
  --query 'NetworkInsightsAccessScopeAnalysis.NetworkInsightsAccessScopeAnalysisId' \
  --output text)"
echo "Started Network Access Scope Analysis: $NAA_ANALYSIS_ID"

while true; do
  STATUS="$(aws ec2 describe-network-insights-access-scope-analyses \
    --region "$REGION" \
    --network-insights-access-scope-analysis-ids "$NAA_ANALYSIS_ID" \
    --query 'NetworkInsightsAccessScopeAnalyses[0].Status' \
    --output text)"
  echo "Scope analysis $NAA_ANALYSIS_ID status: $STATUS"
  if [[ "$STATUS" != "running" ]]; then
    break
  fi
  sleep 5
done

echo "=== 6. Retrieve Network Access Analyzer Findings ==="
aws ec2 get-network-insights-access-scope-analysis-findings \
  --region "$REGION" \
  --network-insights-access-scope-analysis-id "$NAA_ANALYSIS_ID" \
  --max-results 10 \
  --output json

echo ""
echo "Save these IDs for cleanup:"
echo "  SCOPE_ID=$SCOPE_ID"
echo "  NAA_ANALYSIS_ID=$NAA_ANALYSIS_ID"
echo "  WORK_ANALYSIS_ID=$WORK_ANALYSIS_ID"
echo "  BLOCK_ANALYSIS_ID=$BLOCK_ANALYSIS_ID"
