#!/usr/bin/env bash
# Creates a CloudWatch Network Monitoring performance monitor for the lab VPC with the documented CLI.
# hashicorp/aws 6.73.0 has no resource for performance monitors, so this step is outside Terraform.
# Needs a recent AWS CLI v2 that includes the networkflowmonitor *-performance-monitor commands.
# The first monitor in an account creates the shared scope and the service-linked role
# AWSServiceRoleForNetworkFlowMonitor; initialization can take 20 to 30 minutes.
set -euo pipefail
cd "$(dirname "$0")/.."

REGION=$(terraform output -raw create_monitor_command | sed -E 's/.*--region ([^ ]+).*/\1/')
VPC_ARN=$(terraform output -raw vpc_arn)
NAME=${1:-npm-lab-paths}

aws networkflowmonitor create-performance-monitor \
  --region "$REGION" \
  --monitor-name "$NAME" \
  --targets "[{\"type\":\"AWS::EC2::VPC\",\"identifier\":\"$VPC_ARN\"}]"

echo
echo "Monitors in $REGION:"
aws networkflowmonitor list-performance-monitors --region "$REGION"
echo
echo "The create and list output include monitorArn and monitorName but no separate MonitorId field."
echo "Once metrics appear (initial setup can take 20 to 30 minutes, and paths need active traffic),"
echo "read the MonitorId dimension value from CloudWatch:"
echo "  aws cloudwatch list-metrics --region $REGION --namespace AWS/NetworkFlowMonitor --metric-name ImpactScore"
echo "Put that value in performance_monitor_id in terraform.tfvars, then run: terraform apply"
