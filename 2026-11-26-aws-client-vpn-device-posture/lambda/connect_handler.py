"""Sample AWS Client VPN client connect handler Lambda (official v3 schema)."""

import os


def lambda_handler(event, context):
    allowed = {
        p.strip().lower()
        for p in os.environ.get("ALLOWED_PLATFORMS", "mac,win,linux").split(",")
        if p.strip()
    }
    platform = str(event.get("platform", "")).lower()
    common_name = str(event.get("common-name", ""))

    if platform in allowed and common_name:
        return {
            "allow": True,
            "error-msg-on-denied-connection": "",
            "posture-compliance-statuses": ["platform-verified", "cert-present"],
            "schema-version": "v3",
        }

    return {
        "allow": False,
        "error-msg-on-denied-connection": "Connection denied: unsupported OS platform or missing client certificate CN.",
        "posture-compliance-statuses": ["non-compliant-platform"],
        "schema-version": "v3",
    }
