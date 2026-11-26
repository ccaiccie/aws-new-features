#!/usr/bin/env bash
# ==============================================================================
# AWS Shield Advanced — CLI Practice Reference
# ==============================================================================
# Shield control-plane API calls always target --region us-east-1.
# ==============================================================================

# ------------------------------------------------------------------------------
# SECTION 1: SAFE READ-ONLY COMMANDS (Never subscribes, zero Shield charges)
# ------------------------------------------------------------------------------

# 1. Check whether the account is subscribed (ACTIVE or INACTIVE)
aws shield get-subscription-state --region us-east-1

# 2. Describe subscription terms (returns ResourceNotFoundException if not subscribed)
aws shield describe-subscription --region us-east-1

# 3. List protected resources
aws shield list-protections --region us-east-1

# 4. List protection groups
aws shield list-protection-groups --region us-east-1

# 5. List recent DDoS attack summaries
aws shield list-attacks --region us-east-1

# ------------------------------------------------------------------------------
# SECTION 2: DO NOT RUN — PAID SUBSCRIPTION & WRITE REFERENCE COMMANDS
# ------------------------------------------------------------------------------
# WARNING: Running create-subscription triggers a $3,000/month fee with a
# 1-YEAR COMMITMENT plus Data Transfer Out (DTO) usage fees!
# To unsubscribe later, you MUST open an AWS Support case.
# ------------------------------------------------------------------------------

# DO NOT RUN: Subscribe the account ($3,000/mo, 1-year commitment)
# aws shield create-subscription --region us-east-1

# DO NOT RUN: Disable annual auto-renewal (must be done via API/CLI)
# aws shield update-subscription --auto-renew DISABLED --region us-east-1

# DO NOT RUN: Add protection to a specific resource (e.g., CloudFront distribution)
# aws shield create-protection \
#   --name "prod-cloudfront-protection" \
#   --resource-arn "arn:aws:cloudfront::123456789012:distribution/EXAMPLEDISTID" \
#   --region us-east-1

# DO NOT RUN: Create a protection group across all CloudFront distributions
# aws shield create-protection-group \
#   --protection-group-id "prod-web-tier-group" \
#   --aggregation MAX \
#   --pattern BY_RESOURCE_TYPE \
#   --resource-type CLOUDFRONT_DISTRIBUTION \
#   --region us-east-1

# DO NOT RUN: Associate a healthy Route 53 health check for health-based detection
# aws shield associate-health-check \
#   --protection-id "00000000-0000-0000-0000-000000000000" \
#   --health-check-arn "arn:aws:route53:::healthcheck/00000000-0000-0000-0000-000000000000" \
#   --region us-east-1

# DO NOT RUN: Enable SRT proactive engagement (requires Business/Enterprise Support)
# aws shield enable-proactive-engagement --region us-east-1
