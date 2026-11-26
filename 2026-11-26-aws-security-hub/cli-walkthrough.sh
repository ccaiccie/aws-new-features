#!/usr/bin/env bash
# AWS CLI verification and cleanup checks for the Security Hub CSPM single-Region lab.
# Run in your own AWS account after `terraform apply`.

set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"

echo "=== 1. Verify Security Hub CSPM Hub ==="
aws securityhub describe-hub --region "$REGION"

echo "=== 2. List Enabled Standards ==="
aws securityhub get-enabled-standards --region "$REGION" \
  --query 'StandardsSubscriptions[].{Standard:StandardsArn,Status:StandardsStatus}' \
  --output table

echo "=== 3. Inspect Sample Failed or Active Findings (Top 5) ==="
aws securityhub get-findings --region "$REGION" \
  --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' \
  --max-items 5 \
  --query 'Findings[].{Control:Compliance.SecurityControlId,Status:Compliance.Status,Severity:Severity.Label,Title:Title}' \
  --output table

echo "=== 4. List Custom Action Targets ==="
aws securityhub describe-action-targets --region "$REGION" \
  --query 'ActionTargets[].{Name:Name,Arn:ActionTargetArn}' \
  --output table

echo "=== 5. List Automation Rules ==="
aws securityhub list-automation-rules --region "$REGION" \
  --query 'AutomationRulesMetadata[].{Name:RuleName,Order:RuleOrder,Status:RuleStatus}' \
  --output table

echo "=== 6. Check Triage Lambda Logs (after triggering custom action in console) ==="
aws logs tail "/aws/lambda/sechub-lab-triage-handler" --region "$REGION" --since 15m || true

# After running `terraform destroy`, verify Security Hub is disabled in the lab Region:
# aws securityhub describe-hub --region "$REGION"
# Expected result: InvalidAccessException (Account is not subscribed to AWS Security Hub)
