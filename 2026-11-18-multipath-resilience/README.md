# Multipath Resilience: a 99.999% SLA for cross-Region VPC peering and TGW peering

Terraform practice lab for the AWS New Features video "AWS Multipath Resilience: a five-nines SLA for cross-Region traffic" (YouTube playlist **aws new features**, Network Technician channel).

Multipath Resilience became generally available on November 17, 2026. When it is turned on for a cross-Region VPC peering connection, an inter-Region Transit Gateway peering attachment, or cross-Region traffic on AWS Cloud WAN, the AWS network sends copies of each packet across physically diverse backbone paths, delivers the first copy that reaches the destination Region and discards the duplicates. Applications keep one connection and need no code or OS changes. AWS offers a 99.999% **daily** availability SLA on eligible backbone paths.

## Honest limit: no Terraform argument yet

`hashicorp/aws` **6.73.0** (the version pinned here, current when this lab was written on November 18, 2026) has **no argument for Multipath Resilience** on `aws_vpc_peering_connection`, `aws_vpc_peering_connection_accepter` or `aws_ec2_transit_gateway_peering_attachment`. Support is being added upstream (open as of November 18, 2026):

- hashicorp/terraform-provider-aws issue #51076 (VPC peering and TGW peering), PRs #51088 and #51089
- issue #51077 (Cloud WAN core network policy `multipath_resilience` block)

So this lab uses Terraform for everything that **is** supported (the two-Region network, the peering connection and its accepter, optional TGW peering) and turns Multipath Resilience on and off with the AWS CLI in [`scripts/multipath.sh`](./scripts/multipath.sh). Nothing in the `.tf` files pretends to configure the feature. When the provider adds the argument, move the setting into Terraform and stop using the script.

## What it builds

| Piece | Why it matters |
| --- | --- |
| Two providers: `aws.a` (requester, default `us-east-1`) and `aws.b` (accepter, default `us-west-2`) | The feature is cross-Region only; both Regions must be launch Regions |
| `aws_vpc` + two private `aws_subnet` + `aws_route_table` in each Region (`10.10.0.0/16`, `10.20.0.0/16`) | Non-overlapping CIDRs so the VPCs can be peered |
| Security groups allowing ICMP and TCP 5060 from the peer VPC | Test traffic for a SIP-like, latency-sensitive flow; the SLA excludes misconfigured SGs and route tables, so you own these |
| `aws_vpc_peering_connection` (Region A, `peer_region` = Region B) + `aws_vpc_peering_connection_accepter` (Region B) | The connection you enable Multipath Resilience on |
| `aws_route` in each route table to the remote CIDR via the peering connection | Without routes nothing reaches the protected backbone path |
| Optional (`enable_tgw_peering = true`): a transit gateway per Region, VPC attachments, `aws_ec2_transit_gateway_peering_attachment` + `_accepter`, static TGW routes | The second supported connection type; set `route_via = "tgw"` to send VPC traffic over it (VPC routes target the TGW ID, TGW routes target the peering attachment) |

Cloud WAN is the third supported type; it is not built here to keep cost and size down.

## Prerequisites

- An AWS sandbox account and credentials for Terraform and the AWS CLI.
- Terraform 1.6+, provider `hashicorp/aws` 6.73.0 (lock file included).
- A recent AWS CLI v2 that accepts `AllowMultipathResilience` (update the CLI if the option is rejected).
- Both Regions from the launch list: **us-east-1, us-east-2, us-west-1, us-west-2, eu-west-1**, and `region_a` different from `region_b`.

## Cost warning

- VPC peering: Multipath Resilience adds a **per-GB charge on data sent** over the enabled connection to another Region, on top of normal inter-Region data transfer; no Multipath charge for data received. At launch: **$0.015/GB between N. Virginia and Ohio, $0.03/GB for every other supported pair** (AWS example: 100 GB N. Virginia to Oregon = $2.00 transfer + $3.00 Multipath = $5.00).
- TGW peering (optional): transit gateway attachment-hours in both Regions and TGW data processing also apply.
- The lab creates no instances, so with no traffic the peering-only build costs close to nothing. **Run `terraform destroy` when you finish.**

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
terraform apply

# Turn Multipath Resilience on for both sides of the VPC peering connection
scripts/multipath.sh pcx enable "$(terraform output -raw vpc_peering_connection_id)" \
  "$(terraform output -raw region_a)" "$(terraform output -raw region_b)"

# Check: MultipathResilienceStatus pending -> enabled, PeeringOptions.AllowMultipathResilience true on both sides
scripts/multipath.sh pcx status "$(terraform output -raw vpc_peering_connection_id)" \
  "$(terraform output -raw region_a)" "$(terraform output -raw region_b)"
```

The script runs, for the requester Region and then the accepter Region:

```bash
aws ec2 modify-vpc-peering-connection-options --region us-east-1 --vpc-peering-connection-id pcx-... \
  --requester-peering-connection-options AllowMultipathResilience=true
aws ec2 modify-vpc-peering-connection-options --region us-west-2 --vpc-peering-connection-id pcx-... \
  --accepter-peering-connection-options AllowMultipathResilience=true
```

For the optional TGW peering attachment (`enable_tgw_peering = true`):

```bash
scripts/multipath.sh tgw enable "$(terraform output -raw tgw_peering_attachment_id)" \
  "$(terraform output -raw region_a)" "$(terraform output -raw region_b)"
# runs: aws ec2 modify-transit-gateway-peering-attachment --options AllowMultipathResilience=true (both Regions)
```

While only one side allows it, the status is `pending`; once both sides allow it, it becomes `enabled` (mode `always-on`). The peering connection stays `active` (TGW attachment stays `available`) while you enable it.

## Clean up

```bash
scripts/multipath.sh pcx disable "$(terraform output -raw vpc_peering_connection_id)" \
  "$(terraform output -raw region_a)" "$(terraform output -raw region_b)"
terraform destroy
```

Terraform does not know about the CLI change, so `plan` shows no drift for it, and destroying the connection removes it anyway. Disabling first is just tidy.

## How the SLA is measured (read before you rely on it)

From the Multipath Resilience SLA (published November 17, 2026):

- **Daily Uptime of at least 99.999% per Network Path**, where a Network Path is **one direction** of traffic between two endpoints; each direction is measured separately. A Day is 00:00:00 to 23:59:59 UTC.
- An **Unavailable Second** is a second, in a Qualifying Minute, with **more than 10% packet loss**. 99.999% of a day is 0.86 s, so one Unavailable Second misses that Day.
- **Packet delivery**: at least 99.9% of packets over the Day.
- **Qualifying Minute**: the path carries **at least 250,000 packets** in the minute **and no single flow (5-tuple) exceeds 1 Gbps**. Other minutes are not measured.
- Only the **Protected Segment** (the AWS backbone between the Multipath Resilience infrastructure next to each Region) is covered; nothing inside a Region. Misconfigured route tables, security groups, NACLs or VPC settings, and turning the feature off, are excluded.
- Service credits are a percentage of the **Multipath Resilience charges** for the affected path and Day (10% / 25% / 100%), not of data transfer; claim via AWS Support by the end of the second billing cycle after the incident.

A lab with no traffic will never produce Qualifying Minutes; that is expected.

## Experiments

1. Run `status` after enabling only the requester side (comment out the second command in the script): the status stays `pending`.
2. Set `enable_tgw_peering = true` and `route_via = "tgw"`, apply, and look at the VPC route tables: the remote CIDR now targets the transit gateway ID, and the TGW default route tables hold a static route to the peering attachment.
3. Try `region_b = "ap-northeast-1"`: the variable validation refuses it because it is not a launch Region.
4. Remove the remote route from one route table and think about the SLA: this is a customer configuration error, outside the protected segment and excluded.

## References

- AWS What's New, November 17, 2026: https://aws.amazon.com/about-aws/whats-new/2026/11/vpc-tgw-cloudwan-99999-sla/
- VPC Multipath Resilience feature page: https://aws.amazon.com/vpc/features/vpc-multipath-resilience/
- Multipath Resilience SLA: https://aws.amazon.com/vpc/features/vpc-multipath-resilience/sla
- Amazon VPC pricing (Multipath Resilience section): https://aws.amazon.com/vpc/pricing/
- Hands-on test of the CLI options (DevelopersIO, November 18, 2026): https://dev.classmethod.jp/en/articles/vpc-tgw-multipath-resilience-enable/
- Terraform provider tracking issue: https://github.com/hashicorp/terraform-provider-aws/issues/51076
