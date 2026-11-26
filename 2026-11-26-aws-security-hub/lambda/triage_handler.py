import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """Read-only triage handler for Security Hub CSPM Custom Action events."""
    detail = event.get("detail", {})
    action_name = detail.get("actionName", "unknown")
    findings = detail.get("findings", [])

    summaries = []
    for finding in findings:
        compliance = finding.get("Compliance", {})
        severity = finding.get("Severity", {})
        resources = finding.get("Resources", [])
        resource_types = [r.get("Type", "unknown") for r in resources]

        summaries.append(
            {
                "title": finding.get("Title", ""),
                "control_id": compliance.get("SecurityControlId", "n/a"),
                "compliance_status": compliance.get("Status", "n/a"),
                "severity": severity.get("Label", "INFORMATIONAL"),
                "workflow_status": finding.get("Workflow", {}).get("Status", "NEW"),
                "resource_types": resource_types,
            }
        )

    logger.info(
        json.dumps(
            {
                "event_type": event.get("detail-type"),
                "custom_action": action_name,
                "finding_count": len(summaries),
                "summaries": summaries,
            }
        )
    )

    return {"status": "logged", "processed": len(summaries)}
