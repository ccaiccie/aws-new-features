"""Lab responder for GuardDuty, Macie and Security Hub CSPM findings delivered by EventBridge.

Default: log a one-line summary of each finding (CloudWatch Logs).
Optional (ISOLATE=true): for native GuardDuty EC2 findings at or above ISOLATION_MIN_SEVERITY,
replace the instance's security groups with the isolation group, following GuardDuty's
remediation guidance. Changing security groups does not end existing tracked connections;
use a network ACL deny for that.
"""
import json
import os

import boto3

ISOLATE = os.environ.get("ISOLATE", "false") == "true"
SG_ID = os.environ.get("ISOLATION_SG_ID", "")
VPC_ID = os.environ.get("ISOLATION_VPC_ID", "")
MIN_SEV = float(os.environ.get("ISOLATION_MIN_SEVERITY", "7"))


def summarize(event):
    source = event.get("source")
    d = event.get("detail", {})
    if source == "aws.guardduty":
        inst = d.get("resource", {}).get("instanceDetails", {})
        nics = inst.get("networkInterfaces") or [{}]
        return {
            "via": "GuardDuty Finding",
            "type": d.get("type"),
            "severity": d.get("severity"),
            "account": d.get("accountId"),
            "instance": inst.get("instanceId"),
            "vpc": nics[0].get("vpcId"),
            "subnet": nics[0].get("subnetId"),
            "sample": d.get("service", {}).get("additionalInfo", {}).get("sample", False),
        }
    if source == "aws.macie":
        return {
            "via": "Macie Finding",
            "type": d.get("type"),
            "severity": d.get("severity", {}).get("description"),
            "account": d.get("accountId"),
            "bucket": d.get("resourcesAffected", {}).get("s3Bucket", {}).get("name"),
            "sample": d.get("sample", False),
        }
    if source == "aws.securityhub":
        f = (d.get("findings") or [{}])[0]
        return {
            "via": event.get("detail-type"),
            "product": f.get("ProductName"),
            "type": (f.get("Types") or [None])[0],
            "severity": f.get("Severity", {}).get("Label"),
            "workflow": f.get("Workflow", {}).get("Status"),
            "account": f.get("AwsAccountId"),
            "resources": [r.get("Id") for r in f.get("Resources", [])],
        }
    return {"via": "unknown", "source": source}


def isolate(summary):
    instance = summary.get("instance")
    if not (ISOLATE and SG_ID and instance) or summary.get("sample"):
        return "skipped"
    if float(summary.get("severity") or 0) < MIN_SEV:
        return "below threshold"
    ec2 = boto3.client("ec2")
    try:
        res = ec2.describe_instances(InstanceIds=[instance])
        vpc = res["Reservations"][0]["Instances"][0]["VpcId"]
        if vpc != VPC_ID:
            return f"instance in {vpc}, isolation group is in {VPC_ID}"
        ec2.modify_instance_attribute(InstanceId=instance, Groups=[SG_ID])
        return f"isolated with {SG_ID}"
    except Exception as exc:  # lab: report, don't fail the invocation
        return f"isolation failed: {exc}"


def handler(event, context):
    summary = summarize(event)
    if event.get("source") == "aws.guardduty":
        summary["action"] = isolate(summary)
    print(json.dumps(summary, default=str))
    return summary
