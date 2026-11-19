# CloudWatch network path monitoring (Performance Monitor)

Terraform practice lab for the AWS New Features video "CloudWatch network path monitoring: is it the AWS network?" (YouTube playlist **aws new features**, Network Technician channel).

On November 18, 2026 AWS announced **performance monitors** in Amazon CloudWatch Network Monitoring. You select VPCs; Performance Monitor finds the AWS network paths their traffic uses (intra-AZ, AZ to AZ in a Region, inter-Region, and AZ to AWS services such as Amazon S3, DynamoDB, EC2, NAT gateways and transit gateways) and scores each path. It uses telemetry from the AWS infrastructure itself: **no agents, no probes, nothing to open in a security group**. A path appears only when your VPCs have active traffic on it.

| Per path | What it is |
| --- | --- |
| `ImpactScore` | Fixed value per impact level: 0 None, 25 Low, 65 Medium, 95 High. Combines a local comparison (this path vs. its own recent history) and a global comparison (this path vs. all paths AWS measures now); traffic weighted; reported only when degradation persists |
| `RoundTripTimeMs` / `RoundTripTimeP95Ms` | Average and 95th percentile round-trip latency in ms (p95 only when available) |
| `BytesIn` / `BytesOut` | Traffic volume in each direction |

Metrics are in the `AWS/NetworkFlowMonitor` namespace with dimensions `MonitorId`, `LocalLocation`, `RemoteLocation`. There is no monitor-level metric and no subnet-level metric (subnet flows are console drill-down only).

Troubleshooting idea from the announcement: a High impact score on the path your workload uses points to the AWS network (engage AWS Support); a healthy path sends you to your own stack, where Network Flow Monitor agents show per-connection retransmissions and RTT. For hybrid links, Network Synthetic Monitor sends ICMP or TCP SYN probes to on-premises addresses.

## What it builds

| Piece | Resource | Why it matters |
| --- | --- | --- |
| Lab VPC, two private subnets in two AZs, no internet gateway | `aws_vpc`, `aws_subnet` x2, `aws_route_table` | Gives an intra-Region (AZ a to AZ b) path |
| S3 gateway endpoint | `aws_vpc_endpoint` (Gateway) | Gives an AZ-to-service (AZ-Service-AZ) path to Amazon S3 |
| Server (AZ b) and client (AZ a), Amazon Linux 2023 | `aws_instance` x2, `aws_security_group` x2 | The client loops HTTP 8080 + ICMP to the server and HTTPS to S3 every few seconds, because Performance Monitor only shows paths with traffic |
| SNS topic (+ optional email subscription) | `aws_sns_topic`, `aws_sns_topic_subscription` | Alarm target |
| Any-path alarm (after you set `performance_monitor_id`) | `aws_cloudwatch_metric_alarm` with a Metrics Insights `metric_query` | `SELECT MAX(ImpactScore) FROM SCHEMA("AWS/NetworkFlowMonitor", LocalLocation, MonitorId, RemoteLocation) WHERE MonitorId = '<id>'`, threshold 95 (or 65) |
| Dashboard (after you set `performance_monitor_id`) | `aws_cloudwatch_dashboard` | ImpactScore, p95 RTT and BytesOut per path |
| Optional Network Synthetic Monitor | `aws_networkmonitor_monitor`, `aws_networkmonitor_probe` (ICMP) | Only if you set `onprem_probe_destination` and the VPC can actually reach it over DX/VPN |

## Provider gap (read this first)

**hashicorp/aws 6.73.0 (latest at the time of writing) has no resource or data source for Performance Monitor** (`CreatePerformanceMonitor` and related APIs). This lab does **not** fake one. The monitor itself is created with the documented AWS CLI (`aws networkflowmonitor create-performance-monitor`, in a recent AWS CLI v2) by `scripts/create-performance-monitor.sh`, or in the CloudWatch console. Everything around it (VPC, traffic, alarm, dashboard, SNS) is Terraform.

What the provider does have, and why this lab does not use it:

- `aws_networkflowmonitor_scope` manages the **scope** that Performance Monitor shares with Network Flow Monitor. Your first performance monitor creates the scope automatically, a scope can't be deleted while monitors exist, and changes need about 20 minutes between them, so managing it from this lab would fight the console/CLI. Leave it alone unless you already manage your scope in Terraform.
- `aws_networkflowmonitor_monitor` is a **Network Flow Monitor** (agent-based) monitor, a different feature.
- `aws_networkmonitor_monitor` / `aws_networkmonitor_probe` are **Network Synthetic Monitor** (active probes); included here as an optional extra.

The create and list APIs return `monitorArn` and `monitorName`; the `MonitorId` used as the CloudWatch dimension is read from `aws cloudwatch list-metrics` once metrics appear (see step 3).

## Prerequisites

- An AWS account (ideally a sandbox) in one of the 17 Regions where Performance Monitor is available: ap-south-1, ap-northeast-3, ap-northeast-2, ap-southeast-1, ap-southeast-2, ap-northeast-1, ca-central-1, eu-central-1, eu-west-1, eu-west-2, eu-west-3, eu-north-1, sa-east-1, us-east-1, us-east-2, us-west-1, us-west-2.
- Terraform 1.6+, provider `hashicorp/aws` 6.73.0, and AWS CLI v2 recent enough to include the `networkflowmonitor ... performance-monitor` commands.
- Permission to create the service-linked role `AWSServiceRoleForNetworkFlowMonitor` (created automatically on first use; it grants EC2 read-only access for topology mapping, CloudWatch metric publishing, and Organizations read access).

## Cost warning

Performance Monitor pricing: a fixed monthly charge that includes a set volume of network flows across all monitored VPCs, plus a usage charge for flows above that, per million flows per hour (a flow is a unique 5-tuple seen in a five-minute window). The first time you use it you get a 30-day free trial for all your accounts. See "Network Monitoring" on the Amazon CloudWatch pricing page for current rates. Also: two t3.micro instances, the alarm, the dashboard and (optional) Synthetic Monitor probes. **Delete the performance monitor and run `terraform destroy` when you finish.**

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform apply
terraform output
```

### 1. Create the performance monitor (CLI or console)

```bash
./scripts/create-performance-monitor.sh npm-lab-paths
# or: terraform output -raw create_monitor_command   (prints the exact CLI call)
```

Console alternative: CloudWatch > Network Monitoring > **Performance monitors** > Create monitor > accept the service-linked role > name it and select the lab VPC. You can also turn on the recommended High-impact alarm here.

First use in an account initializes Performance Monitor (service-linked role, scope, topology); AWS says this can take **20 to 30 minutes**. Initial path data then takes a few minutes.

### 2. Look at the paths

Console: open the monitor > **Top network paths**. You should see the client AZ to server AZ path (Intra-Region) and the client AZ to Amazon S3 path (AZ-Service-AZ), sorted by impact score, with p95 latency, bytes in/out and path type. Expand a path for its subnet flows. Choose a path for impact and RTT history against the latency baseline, **View in Metrics**, or a one-step alarm.

CLI (TOP_PATHS query: start, poll status, get results):

```bash
./scripts/top-paths.sh npm-lab-paths us-east-1
```

In a healthy lab you will almost certainly see **None** or **Low**. You cannot trigger a High score yourself: it reflects real AWS network degradation, not anything you do inside the VPC.

### 3. Wire the alarm and dashboard

```bash
aws cloudwatch list-metrics --namespace AWS/NetworkFlowMonitor --metric-name ImpactScore
# copy the MonitorId dimension value into terraform.tfvars:
#   performance_monitor_id = "<MonitorId>"
#   impact_alarm_threshold = 95   # or 65 for Medium and above
terraform apply
```

This creates an alarm on a Metrics Insights query (the documented way to alarm on *any* path, because there is no monitor-level metric) and a dashboard grouped by `LocalLocation` / `RemoteLocation`. For a single critical path, create a normal alarm on `ImpactScore` with all three dimensions instead.

### 4. (Optional) Inter-Region scope

If your traffic goes to another Region or account, add the destination account-Region pair on **Account Configuration > Manage Scope**, or accept the recommendation on the monitor page. Without it, inter-Region paths show the destination only as a Region name, without AZ or subnet detail, and scores can look diluted. Wait about 20 minutes between scope changes. A scope holds up to 1,000 account-Region pairs.

### 5. (Optional) Hybrid probes with Network Synthetic Monitor

Only if this VPC can reach an on-premises address (Direct Connect or VPN, not built here): set `onprem_probe_destination` and apply. The ICMP probe from the client subnet publishes round-trip time and packet loss (aggregation 60 s); for Direct Connect destinations the network health indicator (0 or 100) covers the AWS side up to the Direct Connect location. TCP probes rotate the source port across 1024-65535, so on-premises firewalls must allow that range.

## Clean up

```bash
aws networkflowmonitor delete-performance-monitor --monitor-name npm-lab-paths
terraform destroy
```

Deleting the monitor can take about 15 minutes. Delete the **scope** (Account Configuration > Delete scope) only if nothing else in the account uses Performance Monitor or Network Flow Monitor: the scope is shared and deleting it turns off monitoring for both.

## Honest limits

- **No Terraform resource for performance monitors** in hashicorp/aws 6.73.0: CLI/console step above.
- **MonitorId**: not returned as a separate field by create/list; read it from the CloudWatch dimension.
- **You cannot simulate degradation**: the score is computed from AWS infrastructure telemetry compared with history and with other paths; the lab demonstrates setup, paths, metrics and alerting, not a failure.
- **Path level, not proof of impact**: a high score shows degradation on a path your traffic uses; confirm workload impact with application metrics or Network Flow Monitor.
- **One Region, up to 25 VPCs per monitor**; only paths with active traffic appear.
- **Synthetic Monitor** part is optional and needs real hybrid connectivity; the NHI is not accurate for Direct Connect attachments that use intermediary routing with Cloud WAN.

## Sources

- Announcement (November 18, 2026): https://aws.amazon.com/about-aws/whats-new/2026/11/cloudwatch-network-path-monitoring/
- Using Performance Monitor: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor.html
- What is Performance Monitor: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor-What-is.html
- Components (paths, subnet flows, impact score, scope limits): https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor-components.html
- How it works: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor-how-it-works.html
- Metrics: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor-cw-metrics.html
- Alarms: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor-create-alarm.html
- CLI examples: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor-CLI.html
- Regions: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor-Regions.html
- Pricing: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PerformanceMonitor.pricing.html
- Network Synthetic Monitor, how it works: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/nw-monitor-how-it-works.html
- AWS CLI `networkflowmonitor`: https://docs.aws.amazon.com/cli/latest/reference/networkflowmonitor/
