# Practice Lab: AWS WAF & AWS Shield for CloudFront and Application Load Balancer

This compact Terraform and AWS CLI lab deploys a public **Application Load Balancer** (with a lightweight fixed-response `200 OK` backend), an **Amazon CloudFront distribution** fronting that ALB, a **Global AWS WAF web ACL (`CLOUDFRONT` in `us-east-1`)** associated with CloudFront, and a **separate Regional AWS WAF web ACL (`REGIONAL`)** associated with the ALB — complete with AWS Managed Rules, a custom header rule (count or block mode), a rate-based rule, an IP set, and CloudWatch WAF logging.

Intended public repository path:
`https://github.com/ccaiccie/aws-new-features/tree/main/2026-11-26-aws-waf-shield-cloudfront-alb`

## Honest Note on AWS Shield Standard vs Shield Advanced

- **AWS Shield Standard** is already active automatically at no extra Shield cost on your CloudFront distribution and Application Load Balancer.
- **This lab does NOT subscribe to AWS Shield Advanced** (which is a paid opt-in subscription). Never simulate a DDoS attack against a public endpoint.
- For production accounts enrolled in Shield Advanced, this README shows the reference `aws shield create-protection` command for adding CloudFront or ALB protection.

## What This Lab Deploys

1. **VPC & Two Public Subnets** (`10.90.0.0/16`) + **Application Load Balancer** returning a clean JSON `200 OK` fixed response (no EC2 instances needed).
2. **Amazon CloudFront Distribution** using the ALB as its origin, attached to the **Global Web ACL** in `us-east-1`.
3. **Two Separate AWS WAF Web ACLs** (respecting the official rule that a CloudFront web ACL cannot also be associated with an ALB):
   - **Global Web ACL (`us-east-1`, `scope = "CLOUDFRONT"`):** attached to CloudFront, logging to `aws-waf-logs-waf-lab-cf` in `us-east-1`
   - **Regional Web ACL (`var.aws_region`, `scope = "REGIONAL"`):** attached to the ALB, logging to `aws-waf-logs-waf-lab-alb` in `var.aws_region`
4. **Four Rule Types Inside Each Web ACL:**
   - **IP Set** (RFC 5737 documentation example `203.0.113.0/24`, priority 10)
   - **Custom Rule** (`x-lab-block: true` header match, priority 20 — switchable between `count` and `block` via `var.custom_rule_count_mode`)
   - **Rate-Based Rule** (priority 30, default 300 requests per 5 minutes per source IP)
   - **AWS Managed Rule Group** (`AWSManagedRulesCommonRuleSet`, priority 40)

## Prerequisites

- Terraform `>= 1.6` and AWS CLI v2 configured for your lab account.
- **Never commit `terraform.tfvars`, account IDs, or real production IP allow/deny lists.**

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if you want a different aws_region or count mode

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Note outputs (CloudFront takes ~3–5 minutes to finish deploying):
```bash
CF_URL="https://$(terraform output -raw cloudfront_domain_name)"
ALB_URL="http://$(terraform output -raw alb_dns_name)"
```

## Safe Verification Tests (Allow vs Block / Count + WAF Logs)

1. **Allowed request (misses all block rules -> expect HTTP 200):**
   ```bash
   curl -i "$CF_URL/"
   ```
2. **Trigger custom rule (`x-lab-block: true` -> expect HTTP 403 in block mode, or HTTP 200 logged in count mode):**
   ```bash
   curl -i -H "x-lab-block: true" "$CF_URL/"
   curl -i -H "x-lab-block: true" "$ALB_URL/"
   ```
3. **Read WAF CloudWatch Logs (`terminatingRuleId` and `nonTerminatingMatchingRules`):**
   ```bash
   aws logs filter-log-events \
     --region us-east-1 \
     --log-group-name "$(terraform output -raw cf_log_group_name)" \
     --limit 5
   ```
4. **Reference command for Shield Advanced (production accounts only — do NOT run without a Shield Advanced subscription):**
   ```bash
   aws shield create-protection \
     --name "prod-cloudfront-protection" \
     --resource-arn "<CLOUDFRONT_DISTRIBUTION_ARN>"
   ```

## Destroy & Clean Up

Always destroy the lab when done so CloudFront, ALB, AWS WAF web ACLs, and CloudWatch Logs charges stop:

```bash
terraform destroy
```

Confirm cleanup:
```bash
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1
aws wafv2 list-web-acls --scope REGIONAL --region "$(terraform output -raw aws_region 2>/dev/null || echo us-east-1)"
```

## Official AWS Sources

- What are AWS WAF, Shield Advanced, Shield network security director, and Firewall Manager: https://docs.aws.amazon.com/waf/latest/developerguide/what-is-aws-waf.html
- How AWS WAF works: https://docs.aws.amazon.com/waf/latest/developerguide/how-aws-waf-works.html
- Associating a protection pack (web ACL) with an AWS resource: https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html
- AWS Shield chapter: https://docs.aws.amazon.com/waf/latest/developerguide/shield-chapter.html
- Rule actions & WCUs: https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-action.html
- Sending WAF logs to CloudWatch Logs: https://docs.aws.amazon.com/waf/latest/developerguide/logging-cw-logs.html
