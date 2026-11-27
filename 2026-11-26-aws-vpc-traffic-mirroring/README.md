# Amazon VPC Traffic Mirroring Practice Lab

Hands-on Terraform and AWS CLI lab for **Amazon VPC Traffic Mirroring** (source ENI, filter, target ENI, and session) in a disposable VPC.

> **COST WARNING — READ BEFORE DEPLOYING:**
> Each active Amazon VPC Traffic Mirroring session is billed **hourly** until it is deleted — even if you detach the source ENI, stop or terminate the source instance (if the ENI remains), or change the source to an unsupported instance type. Data transfer charges also apply (and load balancer processing charges if you use an NLB or GWLB target). Check the **Network Analysis** tab on the official [Amazon VPC pricing page](https://aws.amazon.com/vpc/pricing/) before deploying, and **delete every traffic mirror session and run `terraform destroy` immediately when finished**.

## Official AWS Documentation Sources

- What is Traffic Mirroring: https://docs.aws.amazon.com/vpc/latest/mirroring/what-is-traffic-mirroring.html
- Traffic Mirroring targets: https://docs.aws.amazon.com/vpc/latest/mirroring/traffic-mirroring-targets.html
- Traffic Mirroring filters: https://docs.aws.amazon.com/vpc/latest/mirroring/traffic-mirroring-filters.html
- Traffic Mirroring sessions: https://docs.aws.amazon.com/vpc/latest/mirroring/traffic-mirroring-sessions.html
- Traffic Mirroring packet format: https://docs.aws.amazon.com/vpc/latest/mirroring/traffic-mirroring-packet-formats.html
- Traffic Mirroring limitations: https://docs.aws.amazon.com/vpc/latest/mirroring/traffic-mirroring-network-limitations.html
- Traffic Mirroring quotas: https://docs.aws.amazon.com/vpc/latest/mirroring/traffic-mirroring-quotas.html
- Amazon VPC Pricing (Network Analysis tab): https://aws.amazon.com/vpc/pricing/

## Lab Architecture

- Disposable VPC (`10.42.0.0/16`) with one subnet (`10.42.1.0/24`) and an Internet Gateway.
- **Mirror Source:** `t3.micro` EC2 instance (`T3` is on the official supported virtualized instance list).
- **Mirror Target:** `t3.micro` EC2 monitoring instance whose security group allows inbound **UDP port 4789** (VXLAN) from the source security group.
- **Traffic Mirror Filter:** Accepts inbound and outbound **TCP 80** (rule 100) and **TCP 443** (rule 110). Because unmatched traffic is not mirrored, SSH (TCP 22) and ICMP are excluded.
- **Traffic Mirror Session:** Connects the source ENI, filter, and target ENI with `session_number = 1` and `virtual_network_id = 100`.

## Option A: Deploy with Terraform

1. Copy the example variables file and set your public IPv4 CIDR (`admin_cidr`) and optional `key_name`:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Initialize, review the plan, and apply:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. Note the Terraform outputs (`source_eni_id`, `source_private_ip`, `source_public_ip`, `target_public_ip`, `traffic_mirror_session_id`).

## Option B: Equivalent AWS CLI Commands

If you already have a supported source ENI (`$SOURCE_ENI`) and a monitoring target ENI (`$TARGET_ENI`) allowing UDP 4789:

```bash
# 1. Create the Traffic Mirror Target
TARGET_ID=$(aws ec2 create-traffic-mirror-target \
  --network-interface-id "$TARGET_ENI" \
  --description "Monitoring appliance ENI target" \
  --query 'TrafficMirrorTarget.TrafficMirrorTargetId' --output text)

# 2. Create the Traffic Mirror Filter
FILTER_ID=$(aws ec2 create-traffic-mirror-filter \
  --description "Mirror TCP 80 and TCP 443 only" \
  --query 'TrafficMirrorFilter.TrafficMirrorFilterId' --output text)

# 3. Add inbound and outbound accept rules for TCP 80 and TCP 443
for DIR in ingress egress; do
  aws ec2 create-traffic-mirror-filter-rule \
    --traffic-mirror-filter-id "$FILTER_ID" \
    --traffic-direction "$DIR" \
    --rule-number 100 \
    --rule-action accept \
    --protocol 6 \
    --destination-port-range FromPort=80,ToPort=80 \
    --source-cidr-block 0.0.0.0/0 \
    --destination-cidr-block 0.0.0.0/0

  aws ec2 create-traffic-mirror-filter-rule \
    --traffic-mirror-filter-id "$FILTER_ID" \
    --traffic-direction "$DIR" \
    --rule-number 110 \
    --rule-action accept \
    --protocol 6 \
    --destination-port-range FromPort=443,ToPort=443 \
    --source-cidr-block 0.0.0.0/0 \
    --destination-cidr-block 0.0.0.0/0
done

# 4. Create the Traffic Mirror Session (hourly billing starts here)
SESSION_ID=$(aws ec2 create-traffic-mirror-session \
  --network-interface-id "$SOURCE_ENI" \
  --traffic-mirror-target-id "$TARGET_ID" \
  --traffic-mirror-filter-id "$FILTER_ID" \
  --session-number 1 \
  --virtual-network-id 100 \
  --description "Mirror web traffic to appliance" \
  --query 'TrafficMirrorSession.TrafficMirrorSessionId' --output text)

aws ec2 describe-traffic-mirror-sessions --traffic-mirror-session-ids "$SESSION_ID"
```

## Verify Matching vs. Non-Matching Flows

1. Connect to the **target** instance and start capturing VXLAN packets on UDP port 4789:

   ```bash
   sudo tcpdump -ni eth0 -vvv udp port 4789
   ```

2. Connect to the **source** instance and generate a **matching** flow (outbound HTTPS on TCP 443):

   ```bash
   curl -I https://aws.amazon.com
   ```

   On the target instance, `tcpdump` displays VXLAN-encapsulated UDP 4789 packets whose **outer source IP** is the source ENI's primary private IP (`source_private_ip`), **VNI** is `100`, and **inner packet** is the TCP 443 flow. (Per AWS official docs, rely on the outer source IP — not the VNI alone — for source attribution.)

3. Next, generate a **non-matching** flow (for example, ICMP echo or SSH TCP 22):

   ```bash
   ping -c 3 1.1.1.1
   ```

   Because the filter only accepts TCP 80 and TCP 443, those ICMP packets do **not** match any rule and do **not** appear in the UDP 4789 capture on the target.

## Teardown & Billing-Stop Verification

Always delete active traffic mirror sessions first and verify zero sessions remain in your Region.

### If deployed with Terraform

```bash
terraform destroy
```

### If deployed with AWS CLI (or to force-clean orphaned sessions)

```bash
aws ec2 delete-traffic-mirror-session --traffic-mirror-session-id "$SESSION_ID"
aws ec2 delete-traffic-mirror-filter --traffic-mirror-filter-id "$FILTER_ID"
aws ec2 delete-traffic-mirror-target --traffic-mirror-target-id "$TARGET_ID"
```

### Verify Zero Active Sessions Remain

```bash
aws ec2 describe-traffic-mirror-sessions \
  --query 'TrafficMirrorSessions[*].[TrafficMirrorSessionId,NetworkInterfaceId]' \
  --output table
```

Confirm the command returns an empty result so hourly Traffic Mirroring charges stop.
