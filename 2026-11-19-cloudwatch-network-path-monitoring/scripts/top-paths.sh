#!/usr/bin/env bash
# Runs a TOP_PATHS query for the last hour, as documented for Performance Monitor.
# Usage: scripts/top-paths.sh <monitor-name> [region]
set -euo pipefail
NAME=${1:?monitor name}
REGION=${2:-us-east-1}
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)

QID=$(aws networkflowmonitor start-query-performance-monitor --region "$REGION" \
  --monitor-name "$NAME" --query-type TOP_PATHS --start-time "$START" --end-time "$END" \
  --query queryId --output text)
echo "queryId: $QID"

for _ in $(seq 1 30); do
  STATUS=$(aws networkflowmonitor get-query-status-performance-monitor --region "$REGION" \
    --monitor-name "$NAME" --query-id "$QID" --query status --output text)
  echo "status: $STATUS"
  [ "$STATUS" = "SUCCEEDED" ] && break
  case "$STATUS" in FAILED|CANCELED) exit 1 ;; esac
  sleep 5
done

aws networkflowmonitor get-query-results-performance-monitor --region "$REGION" \
  --monitor-name "$NAME" --query-id "$QID"
