# VPC Flow Logs version 11: resource tags and next-hop fields

Terraform practice lab for the AWS New Features video "VPC Flow Logs v11: Resource Tags and Next-Hop Fields" (YouTube playlist **aws new features**, Network Technician channel).

On June 10, 2026 AWS added two kinds of metadata to VPC Flow Logs (record version 11):

- **EC2 resource tag fields**: `instance-tag`, `instance-tag-2`, `interface-tag`, `interface-tag-2`, `asg-tag`, `asg-tag-2`. You choose which tag keys fill them with a `TagFieldSpecification` (Terraform: `tag_field_specification`).
- **Next-hop fields**: `next-hop-interface-id`, `next-hop-subnet-id`, `next-hop-az-id`, `next-hop-vpc-id`, `next-hop-interface-type`, plus `interface-type` for the interface that captured the flow.

This lab builds a small VPC that produces accepted, rejected and NAT-translated traffic, and a flow log whose custom format includes these fields alongside the older ones (`pkt-srcaddr`, `pkt-dstaddr`, `flow-direction`, `traffic-path`, `reject-reason`).

## What it builds

| Piece | Why it matters |
| --- | --- |
| VPC `10.42.0.0/16`, one public subnet with a NAT gateway, one private subnet | Private instances reach the internet through the NAT gateway, so you see the NAT interface and its translation |
| Instance `orders-web` (tags `app=orders-web`, `team=payments`, ENI tag `role=frontend`) | Every 30 seconds: HTTPS to the internet, TCP 8080 to the db tier, TCP 22 to the db tier |
| Instance `orders-db` (tags `app=orders-db`, `team=payments`, ENI tag `role=database`) | Security group allows only TCP 8080 from the web tier, so the TCP 22 attempt is **REJECT** |
| CloudWatch Logs log group + IAM role for flow log delivery | Destination for the records (about 5 minutes delivery delay) |
| `aws_flow_log` on the VPC, `traffic_type = ALL`, 60-second aggregation, custom version 11 format | Tag fields from `tag_field_specification`: instance keys `app`, `team`; network-interface key `role` |
| Three saved Logs Insights queries | Rejects by tag, egress next hops, NAT gateway original addresses |
| Optional (`enable_s3_parquet = true`): S3 bucket + second flow log in Parquet with Hive-compatible hourly partitions | The same records ready for Athena |

## Prerequisites

- An AWS account you can experiment in (ideally a sandbox) and credentials for Terraform (`aws sts get-caller-identity` works in your terminal).
- Terraform 1.6 or later. The `hashicorp/aws` provider is pinned to 6.73.0; `tag_field_specification` needs 6.56.0 or later.
- AWS CLI v2 for the verification steps, and the Session Manager plugin if you want a shell on the instances.
- A Region where the version 11 fields are available (for example `us-east-1`, `us-east-2`, `us-west-2`).
- IAM permissions for EC2, VPC, IAM, CloudWatch Logs and (optionally) S3. Tag fields also need `ec2:DescribeTags` and `iam:CreateServiceLinkedRole`: the first flow log with tag fields creates the Flow Logs EC2 Tags service-linked role and EventBridge managed rules in your account. Do not delete those managed rules by hand; they are cleaned up when the last tag-field subscription is deleted.

## Cost warning

The NAT gateway (hourly plus per GB), two `t3.micro` instances, and CloudWatch Logs ingestion cost money while the lab runs, roughly ten cents an hour in `us-east-1`. **Run `terraform destroy` when you finish.**

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars   # adjust region/name if you like
terraform init
terraform validate
terraform plan
terraform apply
terraform output
```

Wait about 10 minutes after `apply`: the instances boot, the traffic loop starts, and flow log delivery to CloudWatch Logs takes about 5 minutes. Tag values can be missing or inaccurate during the first hour of a new subscription.

## Expected results

In the log group `/vpc-flow-logs/flowlogs-v11` you will see records like these (fields in the order of the `log_format` output):

1. **Web to internet, on the web instance interface (egress)**: `action ACCEPT`, `instance-tag orders-web`, `interface-tag frontend`, `traffic-path 1` (through another resource in the same VPC), `next-hop-interface-type nat_gateway`, `next-hop-subnet-id` = the public subnet.
2. **The same flow on the NAT gateway interface**: `interface-type nat_gateway`, `srcaddr` = web private IP, `dstaddr` = the NAT gateway private IP, `pkt-dstaddr` = the real internet destination. Outbound from the NAT gateway, `traffic-path 8` (internet gateway).
3. **Web to db TCP 8080**: `ACCEPT` on both interfaces; on the db interface `instance-tag orders-db`.
4. **Web to db TCP 22**: on the db interface, `action REJECT`, `flow-direction ingress`, `instance-tag orders-db`, `interface-tag database`, `reject-reason -` (security group rejects are not BPA or encryption-control rejects).

## Verification

```bash
LG=$(terraform output -raw log_group_name)

# 1. The flow log is active and uses your format
aws ec2 describe-flow-logs --flow-log-ids "$(terraform output -raw flow_log_id)" \
  --query "FlowLogs[0].[FlowLogStatus,DeliverLogsStatus,LogFormat]"

# 2. Raw records containing a REJECT
aws logs filter-log-events --log-group-name "$LG" --filter-pattern '"REJECT"' --max-items 5 \
  --query "events[].message" --output text

# 3. Run the saved query "flowlogs-v11/1-rejects-by-tag" in the CloudWatch console (Logs Insights > Saved queries),
#    or from the CLI:
QUERY="$(terraform output -raw logs_insights_parse) | filter action = \"REJECT\" | stats count(*) as rejects by instance_tag, interface_tag, dstport"
QID=$(aws logs start-query --log-group-name "$LG" --start-time $(( $(date +%s) - 3600 )) --end-time $(date +%s) \
  --query-string "$QUERY" --query queryId --output text)
sleep 10; aws logs get-query-results --query-id "$QID"
```

You should see rejects grouped under `orders-db` / `database` with `dstport 22`. The saved query `2-egress-next-hops` shows `orders-web` egress with `next_hop_interface_type nat_gateway`; `3-nat-gateway-original-addresses` shows `dstaddr` (NAT private IP) next to `pkt_dstaddr` (the real destination).

### Optional: Parquet in S3 for Athena

Set `enable_s3_parquet = true` and apply again. Objects appear under `AWSLogs/aws-account-id=<id>/aws-service=vpcflowlogs/aws-region=<region>/year=/month=/day=/hour=/` about 10 minutes later. Create an Athena table over that prefix with partition projection or with the flow log's **Athena integration** in the VPC console. Tag values are UTF-8 percent-encoded; decode them with `url_decode(instance_tag)`.

## Experiments

1. Change the db security group to also allow TCP 22 from the web tier and apply. The REJECT records for port 22 stop (after the delivery delay).
2. Change the `app` tag on `orders-web` to `orders-web-v2`. Within a few minutes new records carry the new value; you never had to join the logs with an inventory.
3. Swap the instance tag keys to `["team", "app"]`. Flow log configuration is immutable, so Terraform replaces the flow log; afterwards `instance-tag` holds the team and `instance-tag-2` holds the app.
4. Set `aggregation_interval = 600`. On Nitro instances such as `t3`, records still arrive per minute or less.

## Cleanup

```bash
terraform destroy
```

This removes the instances, NAT gateway, Elastic IP, flow logs, log group, saved queries, IAM roles and (if enabled) the S3 bucket and its objects. The Flow Logs EC2 Tags service-linked role and its EventBridge managed rules are cleaned up by AWS after the last tag-field subscription is deleted.

## References

- Flow log records and available fields: https://docs.aws.amazon.com/vpc/latest/userguide/flow-log-records.html
- Flow log limitations (tag and next-hop fields): https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-limitations.html
- What's New, June 10, 2026: https://aws.amazon.com/about-aws/whats-new/2026/06/amazon-flow-logs-metadata/
- CreateFlowLogs API (TagFieldSpecification): https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_CreateFlowLogs.html
- Terraform `aws_flow_log`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log
