# Route 53 private endpoint health checks

Terraform practice lab for the AWS New Features video "Route 53 private endpoint health checks: DNS failover for private apps" (YouTube playlist **aws new features**, Network Technician channel).

On November 19, 2026 AWS announced **Amazon Route 53 Private Endpoint Health Checks**. Route 53 can now health check targets that never touch the internet (internal APIs, databases, servers in private subnets, on-premises systems reachable from a VPC over Direct Connect or Site-to-Site VPN) by IP address or domain name, over HTTP, HTTPS or TCP, and use those checks for DNS records in **private hosted zones** under any routing policy. AWS says detection and failover are designed to complete in seconds rather than minutes. Available in all AWS commercial Regions.

How it works (three stages):

1. **Health check source**: a VPC plus one subnet in each of three Availability Zones (two in US West (N. California)), each with 1 to 10 security groups. Route 53's service-linked role `AWSServiceRoleForRoute53PrivateHealthChecks` creates ENIs (Name tag `healthchecksource-...`) in those subnets; health check traffic comes from those private IPs. One source supports up to 200 checks; up to 5 sources per account; the network configuration can't be changed after creation.
2. **Private endpoint health check**: `EndpointType = PRIVATE` + `HealthCheckSourceId`, target IP or domain name, protocol, port, path. 30-second (standard) or 10-second (fast) interval; healthy = 2xx/3xx in time (HTTP/HTTPS) or a TCP connection; status flips after the failure threshold (default 3). Optional string matching.
3. **DNS records**: associate the check with records in a private hosted zone (same account only).

Key limits from the docs: a private check is **Regional** (it runs from, and its status/metrics/alarms are in, the source's Region); one source per check; check and records in the same account; at launch **no calculated health checks referencing private checks** and no private + public combination; `EndpointType` can't change after creation. Domain names resolve **only through the VPC Route 53 Resolver**, not DNS servers from your DHCP options set.

## What it builds

| Piece | Resource | Why it matters |
| --- | --- | --- |
| VPC with private subnets in three AZs, no internet gateway or NAT | `aws_vpc`, `aws_subnet` x3, `aws_route_table` | A source needs one subnet per AZ in three AZs |
| Primary (subnet 1, `10.20.1.10`) and secondary (subnet 2, `10.20.2.10`) web servers on Amazon Linux 2023 | `aws_instance` x2 | `python3 -m http.server 8080` answers `GET /health` with 200 |
| Source SG (egress 8080 to the app SG) and app SG (ingress 8080 from the source SG) | `aws_security_group`, `aws_vpc_security_group_*_rule` | The rules a network technician must open |
| Health check source + two private HTTP checks | `aws_cloudformation_stack` with `AWS::Route53::HealthCheckSource` and `AWS::Route53::HealthCheck` | See the provider gap below |
| Private hosted zone `lab.internal` with a failover pair `app.lab.internal` (TTL 10) | `aws_route53_zone`, `aws_route53_record` x2 | PRIMARY -> 10.20.1.10, SECONDARY -> 10.20.2.10 |
| Alarm on the primary check + SNS topic (optional email) | `aws_cloudwatch_metric_alarm` (`AWS/Route53` `HealthCheckStatus`, Minimum < 1), `aws_sns_topic` | Created in the source Region |
| Optional test client with SSM endpoints | `aws_instance`, `aws_vpc_endpoint` x3 (ssm, ssmmessages, ec2messages) | Resolve the record from inside the VPC with Session Manager |

## Provider gap (read this first)

**hashicorp/aws 6.73.0 (latest at the time of writing, published November 11, 2026, before this launch) has no resource for a health check source, and `aws_route53_health_check` has no `endpoint_type` or `health_check_source_id` argument.** Open requests: [hashicorp/terraform-provider-aws#51152](https://github.com/hashicorp/terraform-provider-aws/issues/51152) (new resource `aws_route53_health_check_source`) and [#51153](https://github.com/hashicorp/terraform-provider-aws/issues/51153) (`endpoint_type` and `health_check_source_id` on `aws_route53_health_check`).

This lab does **not** fake those resources. CloudFormation documents `AWS::Route53::HealthCheckSource` and the `EndpointType` / `HealthCheckSourceId` properties of `AWS::Route53::HealthCheck`, so `healthchecks.tf` deploys the source and both checks in a real `aws_cloudformation_stack` and reads the IDs from its outputs. Everything else is native Terraform. When the provider adds support, replace the stack with native resources.

Other honest notes:

- The configuration passes `terraform fmt` and `terraform validate` with hashicorp/aws 6.73.0. It was not applied in a live account while writing this lab, so treat the CloudFormation part as new-launch territory. If the stack fails, read the stack events and the source's `StatusReasonCode`.
- If a check is created before the source reaches `Available` (`CREATE_COMPLETED`) and the stack fails, run `terraform apply` again.
- The AWS CLI calls for the source are `aws route53 create-health-check-source`, `get-health-check-source`, `list-health-check-sources`, `list-health-checks-by-source` and `delete-health-check-source` in an AWS CLI version new enough to include them.

## Permissions

The identity that runs Terraform needs EC2, Route 53, CloudFormation, CloudWatch, SNS and (for the client) IAM permissions, **plus `iam:CreateServiceLinkedRole`** for `route53healthchecks.amazonaws.com`. Route 53 checks that permission on **every** `CreateHealthCheckSource` **and** `DeleteHealthCheckSource` call, even after the role exists; without it the call fails immediately with `AccessDenied` (HTTP 403). `AmazonRoute53FullAccess` includes it; in a custom policy, scope it with `iam:AWSServiceName = route53healthchecks.amazonaws.com`.

## Cost (Route 53 pricing page, November 2026)

- Health check source: **$0.125 per hour per AZ association, minimum 3 AZs** (about $0.375 per hour for this lab's source), metered hourly.
- Health checks: **$0.50 per check per month** (HTTP, TCP); **+$1.00 per month each** for HTTPS, string matching, fast interval. Prorated.
- Plus three t3.micro instances, three interface endpoints (if `enable_test_client = true`), CloudWatch and SNS.

**Run `terraform destroy` as soon as you finish.**

## Steps

1. `cp terraform.tfvars.example terraform.tfvars` and adjust. Use a Region with at least three AZs.
2. `terraform init && terraform apply`. The source takes a few minutes to provision.
3. Route 53 console > **Health checks** > **Health check sources**: the source shows **Available**. On the **Health checks** tab both checks turn healthy after a short while. Metrics and the alarm are in **your lab Region** (not us-east-1).
4. Connect to the test client: `aws ssm start-session --target $(terraform output -raw test_client_instance_id)`, then:

   ```bash
   getent ahostsv4 app.lab.internal      # expect 10.20.1.10 (primary)
   curl -s http://app.lab.internal:8080/health
   ```

5. Break the primary: `aws ec2 stop-instances --instance-ids $(terraform output -raw primary_instance_id)`. After `failure_threshold` failed checks the primary check goes unhealthy, the alarm fires, and `getent ahostsv4 app.lab.internal` returns **10.20.2.10**.
6. `aws ec2 start-instances ...` the primary and watch the answer move back.
7. Optional experiments: remove the `hc_source_to_app` egress rule (checks fail), set `request_interval = 10`, or point a copy of the check at an on-premises IP reachable over your VPN/Direct Connect (open your on-prem firewall for the three source subnets).
8. `terraform destroy`. Health checks must be gone before the source can be deleted; the stack handles the order.

## Troubleshooting order

1. Source **Available**? If **Create failed**, read the reason code: `INSUFFICIENT_SUBNET_IPS`, `EC2_LIMIT_EXCEEDED`, `INVALID_SUBNET` (wrong ID, or the AZ ID doesn't match the subnet), `INVALID_SECURITY_GROUP`, `INVALID_CONFIGURATION`, `SLR_MISSING_OR_NOT_ASSUMABLE`, `INTERNAL_ERROR`.
2. Path: source SG egress, target SG ingress, network ACLs both ways (stateless: allow ephemeral return ports), on-prem routes and firewalls.
3. Name: if you check a domain name, can the VPC Resolver resolve it? If not: associate the private hosted zone, add a Resolver forwarding rule, or check by IP.
4. App: does the path return 2xx/3xx in time? Does the body contain the search string (first 5,120 bytes)?

## Sources

- What's New, November 19, 2026: https://aws.amazon.com/about-aws/whats-new/2026/11/route-53-private-endpoint-health-checks/
- Private endpoint health checks: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-private-endpoints.html
- Health check sources: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-check-sources.html
- Service-linked role: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/using-service-linked-roles-private-endpoint-health-checks.html
- How Route 53 determines health: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover-determining-health-of-endpoints.html
- CloudWatch metrics for health checks: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/monitoring-cloudwatch.html
- CloudFormation `AWS::Route53::HealthCheckSource`: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-route53-healthchecksource.html
- Route 53 pricing: https://aws.amazon.com/route53/pricing/
