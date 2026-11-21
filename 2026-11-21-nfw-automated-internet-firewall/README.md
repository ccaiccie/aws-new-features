# AWS Network Firewall automated Internet firewall (public preview)

Terraform practice lab for the AWS New Features video "Network Firewall automated Internet firewall: inspection at the internet gateway" (YouTube playlist **aws new features**, Network Technician channel).

On November 20, 2026 AWS announced the public preview of **automated Internet firewall**, a deployment mode of AWS Network Firewall. You define Network Firewall rules centrally in **AWS Network Security Manager (NSM)**, and AWS enforces them, with **native NAT**, directly at the **internet gateway** of every VPC in scope: all inbound and outbound traffic that crosses the internet gateway is inspected, with no routing or architecture changes inside the VPCs. Scope can be specific VPCs, an account, OUs or the whole organization, and can cover future VPCs and subnets automatically. Preview Regions: all AWS Regions except AWS GovCloud (US) and China.

How it works (from the Network Firewall and NSM developer guides):

- **Inline at the IGW.** Every connection into or out of an in-scope VPC passes through the firewall. Because inspection is at the internet gateway and not at a hop reached through a route table, no subnet or gateway route change inside the VPC can route traffic around it.
- **Modes.** `ENFORCE` drops traffic that matches block or drop rules. `MONITOR` evaluates and logs everything but blocks nothing (the console wizard default; recommended first).
- **NSM objects.** *Rules* (one setting each: a rule group entry, an IPS rule group entry, `PolicyMode`, `FirewallDefaultAction`, `StatefulEngineOptions`, or `LoggingConfiguration`) → optional *templates* (up to 50 rules) → a *policy* (up to 100 items, at most 2 templates; priority; default subnet connectivity; overrides) → a *scope* (which VPCs) → a *deployment* (policy + scope). NSM then creates one `igw-firewall` per VPC, named `arn:aws:network-firewall:<region>:<account-id>:igw-firewall/<vpc-id>`, and keeps it in sync. The firewall is **read-only** in Network Firewall; changes through the Network Firewall API fail.
- **Priority.** Lower number = higher priority. For IGW firewall policies only the highest-priority policy that applies to a VPC takes effect; lower-priority settings are not merged.
- **Subnet connectivity types.** `bidirectional` (public-IP resources in and out; resources without a public IP can't reach the internet), `outbound-only` (unsolicited inbound dropped; IPv4 NAT after inspection; no NAT for IPv6), `flexible` (recommended: per resource; public IP + subnet routed to the IGW = bidirectional; routed to a NAT gateway = outbound-only; no public IP = outbound-only through native NAT), `exclude` (not inspected) and `az-unsupported` (assigned automatically). Overrides match subnets by ARN or tag; the first matching override wins.
- **Native NAT.** NAT IPs are Elastic IPs allocated **in your account** by the firewall's service-linked role: one per AZ to start, growing with NAT port usage up to 8 per AZ, separate per VPC. Use an IPAM policy with resource type `igw-firewall` (BYOIP or an Amazon-provided contiguous block) to control them. In flexible mode, traffic that already has a public IP or comes from a NAT gateway is filtered but **not re-translated**.

> **Trap:** in flexible mode, a subnet whose route table already sends `0.0.0.0/0` to the internet gateway **gains outbound internet access** for resources that have no public IP and no NAT gateway. Exclude intentionally isolated subnets **before** you create the deployment. This lab does exactly that with a tag-based `exclude` override.

## What it builds

| Piece | Resource | Why it matters |
| --- | --- | --- |
| VPC `10.40.0.0/16` tagged `internet-inspection = enabled`, internet gateway, **one AZ** | `aws_vpc`, `aws_internet_gateway` | The NSM VPC scope selects this tag. Charges are per VPC per AZ, so the lab stays in one AZ |
| Three subnets sharing one route table with only `0.0.0.0/0 -> igw` | `aws_subnet` x3, `aws_route_table`, `aws_route` | No NAT gateway, no firewall subnets, no IGW edge route table |
| Public subnet `10.40.1.0/24` + instance with a public IP (`python3 -m http.server 8080`) | `aws_instance.public` | Flexible: bidirectional, keeps its own IP |
| Private subnet `10.40.2.0/24` + instance **without** a public IP | `aws_instance.private` | Flexible: outbound-only through the firewall's native NAT |
| Isolated subnet `10.40.3.0/24` tagged `network-zone = isolated` (it has the IGW route on purpose) | `aws_subnet.isolated` | Overridden to `exclude`, so it does **not** gain native NAT egress |
| Session Manager role for both instances | `aws_iam_role`, `aws_iam_instance_profile` | No SSH; the private instance reaches SSM through native NAT once the firewall is Ready |
| NSM mode rule (+ optional IPS rule-group rules), template, isolated-subnet override scope, policy (flexible + exclude override, `RemediationEnabled`), VPC scope, deployment | `aws_cloudformation_stack` with `AWS::NetworkSecurityManager::Rule` / `Template` / `Scope` / `Policy` / `Deployment`, `FirewallType = IGW_FIREWALL` | See the provider gap below |

## Provider gap (read this first)

**hashicorp/aws 6.73.0 (latest at the time of writing) has `aws_networksecuritymanager_rule`, `_template`, `_policy`, `_scope` and `_deployment`, but not the automated Internet firewall settings:** `aws_networksecuritymanager_policy` has only a `waf_config` block (no `IgwFirewallConfig`: `DefaultSubnetConnectivity`, `SubnetConnectivityOverrides`), and `aws_networksecuritymanager_scope` has no `specialized_scope_type` (needed for an `IGW_FIREWALL_SUBNET_CONNECTIVITY_OVERRIDE` scope). Open requests: [hashicorp/terraform-provider-aws#51208](https://github.com/hashicorp/terraform-provider-aws/issues/51208) and [#51209](https://github.com/hashicorp/terraform-provider-aws/issues/51209).

This lab does **not** fake those settings. CloudFormation documents every piece, so `firewall.tf` deploys the NSM objects in a real `aws_cloudformation_stack` (built with `jsonencode`) and reads the policy and deployment ARNs from its outputs. Everything else is native Terraform. When the provider adds support, replace the stack with native resources.

Other honest notes:

- The configuration passes `terraform fmt` and `terraform validate` with hashicorp/aws 6.73.0. It was **not applied in a live account** while writing this lab; the feature is in preview, so treat the CloudFormation part as new-launch territory and read the stack events if it fails.
- CloudFormation does not validate the JSON in `ScopeConfiguration` and rule `Configuration`; errors show up when the stack is provisioned. Rule configurations are validated by an NSM dry run with **your** credentials (`network-firewall:CreateFirewallPolicyV2` and `network-firewall:TagResource` for inspection rules).
- Single-account mode omits `AccountFilter` from the VPC scope. Set `multi_account = true` only from an NSM administrator account (Organizations with all features, trusted access for NSM, administrator registered in this Region). A scope's mode can't be switched later.
- The lab policy contains only the `PolicyMode` rule unless you pass IPS rule-group ARNs in `managed_ips_rule_group_arns` (find managed groups with `aws network-firewall list-rule-groups --scope MANAGED`). In the console you can instead add the AWS managed template **AWSManagedTemplateIGWFirewallBaseline** (blocks known attack infrastructure, malware distribution and botnet C2 domains with managed IPS rule groups; default action ACCEPT). Logging (alert and/or flow logs to S3, CloudWatch Logs or Firehose) is a `LoggingConfiguration` configuration rule; add it in the NSM policy editor.
- Manage the deployment **only** through this stack: NSM uses optimistic concurrency, and edits made in the console between CloudFormation's read and write make the stack operation fail.

## Preview limits (from the docs)

- Not compatible with Regional NAT, noNAT ingress routing, or ingress-only VPC Block Public Access.
- No NAT64: keep a NAT gateway for IPv6-to-IPv4 traffic.
- Not in Local Zones; only in AZs where Network Firewall is available. Not for EC2 Mac instances or p4d, p4de, p6-b200, p6-b300, p6e-gb200, trn2, trn2u and g7e instances.
- Traffic to services through **VPC gateway endpoints** never crosses the internet gateway and is not inspected.
- Throughput: 100 Gbps per AZ per VPC (not adjustable). NSM quotas (per account and Region, not adjustable): 200 rules, 100 templates, 100 policies, 100 scopes, 100 deployments; 1 to 2 policies and exactly 1 scope per deployment.

## Cost

Automated internet firewall charges **per VPC in each Availability Zone per hour, plus a per-GB fee for inspected traffic**; NSM also charges per protected resource. Check the [Network Firewall pricing](https://aws.amazon.com/network-firewall/pricing/) and NSM pricing pages before you deploy. Plus two t3.micro instances and their public IPv4 addresses (including the firewall's NAT EIPs).

**Run `terraform destroy` as soon as you finish.**

## Steps

1. `cp terraform.tfvars.example terraform.tfvars` and adjust (keep `policy_mode = "MONITOR"` for the first run; pick an unused `policy_priority`).
2. `terraform init && terraform apply`. The stack finishes when the deployment is published; provisioning is **asynchronous**, and a deployment status of Active does not mean the firewall is built.
3. NSM console > **Deployments** > your deployment > **Synchronization**: wait for the VPC to show **In sync**. Amazon VPC console > **Network Firewall** > **Firewalls** > **Internet firewalls** tab: the firewall (named after the VPC ID) goes from **Provisioning** to **Ready**. An AZ with no active network interface shows **Standby** (a stopped instance does not count).
4. Open the firewall > **NAT IPs** tab and note the Elastic IP.
5. Private instance: `aws ssm start-session --target <private_instance.id>` then `curl -s https://checkip.amazonaws.com` - expect the firewall NAT IP. Public instance: the same command returns its own public IP (bidirectional, not re-translated).
6. Optional inbound test: set `test_client_cidr` to your IP `/32`, apply, and `curl http://<public_ip>:8080/` - the connection is inspected at the IGW.
7. Create a VPC flow log with a custom format that includes `traffic-path`; egress from the instances processed by the firewall shows **`9`** (ingress always shows `-`).
8. Set `policy_mode = "ENFORCE"`, apply, and test a domain that your rule groups block.
9. `terraform destroy`. CloudFormation deletes the deployment, scopes, policy, template and rules in reverse order, and NSM removes the igw-firewall.

## Troubleshooting order

1. Stack events: invalid `ScopeConfiguration`/`Configuration` JSON, a `Priority` already used by another policy, or missing NSM / Network Firewall permissions.
2. Deployment **Synchronization** tab: Out of sync reasons and remediation issues.
3. Firewall status per AZ: **Standby** means no active network interface in that AZ yet.
4. Private instance has no internet: is the subnet routed to the IGW, is its connectivity flexible or outbound-only (not excluded), and is the firewall Ready?
5. Unexpected egress from an isolated subnet: add an `exclude` override (tag or ARN), or remove its IGW route.

## Sources

- What's New, November 20, 2026: https://aws.amazon.com/about-aws/whats-new/2026/11/network-firewall-automated-internet/
- Automated Internet Firewall: https://docs.aws.amazon.com/network-firewall/latest/developerguide/internet-gateway-firewall.html
- How it works: https://docs.aws.amazon.com/network-firewall/latest/developerguide/internet-gateway-firewall-how-it-works.html
- Getting started: https://docs.aws.amazon.com/network-firewall/latest/developerguide/internet-gateway-firewall-getting-started.html
- Existing architectures: https://docs.aws.amazon.com/network-firewall/latest/developerguide/internet-gateway-firewall-existing-architectures.html
- Logging and monitoring: https://docs.aws.amazon.com/network-firewall/latest/developerguide/internet-gateway-firewall-logging-monitoring.html
- Quotas: https://docs.aws.amazon.com/network-firewall/latest/developerguide/internet-gateway-firewall-quotas.html
- NSM: Automated Internet Firewall: https://docs.aws.amazon.com/network-security-manager/latest/devguide/managing-internet-gateway-firewall.html
- NSM concepts: https://docs.aws.amazon.com/network-security-manager/latest/devguide/concepts.html
- NSM quotas: https://docs.aws.amazon.com/network-security-manager/latest/devguide/quotas.html
- CloudFormation: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-networksecuritymanager-rule.html (also `-template`, `-policy`, `-scope`, `-deployment`)
- IPAM policies for automated internet firewall (What's New, November 20, 2026): https://aws.amazon.com/about-aws/whats-new/2026/11/vpc-ipam-policies-firewall-lambda/
