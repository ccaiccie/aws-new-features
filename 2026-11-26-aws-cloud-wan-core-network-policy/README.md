# AWS Cloud WAN Unit 4 Practice Lab: Core Network Policy, Segments, and Attachment Types

> **COST AND TIMING WARNING:** AWS Cloud WAN core networks, core network edges (CNEs), and attachments bill hourly until they are deleted. Per official AWS Cloud WAN pricing, each Core Network Edge bills **$0.50 USD per hour** regardless of Region (partial hours rounded up), and VPC attachments bill at a Regional hourly rate (for example, **$0.065 USD per hour** in `us-east-1`), plus data processing ($0.02/GB in `us-east-1`) and any standard AWS Data Transfer charges. Any Transit Gateway or Site-to-Site VPN resources you attach also bill separately until deleted. Provisioning and teardown of a Cloud WAN core network and attachments commonly take **10 to 20 minutes**—do not leave this lab running overnight. Always run `terraform destroy` when finished and verify in the AWS CLI or console that all resources are deleted.

## What This Lab Builds

This Terraform and AWS CLI lab builds a single-Region AWS Cloud WAN core network (default `us-east-1`) with:

- **1 Global Network** (`aws_networkmanager_global_network`)
- **1 Core Network** (`aws_networkmanager_core_network`) with a core network policy document (`version = "2021.12"`; AWS also supports `2025.11` for routing policies/BGP communities and `2026.10` for default cross-Region MED tie-breaking)
- **2 Network Segments**: `prod` and `shared`
- **Tag-based Attachment Policy** (Rule `100`): maps any attachment carrying a `Segment` tag directly to the matching segment name
- **2 VPCs & VPC Attachments**:
  - `prod` VPC (`10.10.0.0/16`) tagged `Segment = "prod"`
  - `shared` VPC (`10.20.0.0/16`) tagged `Segment = "shared"`
- **Allow vs. Block Sharing Toggle**:
  - Default (`allow_prod_shared_sharing = false`): `prod` and `shared` are isolated (no `segment-actions` share rule).
  - Enabled (`allow_prod_shared_sharing = true`): adds a `segment-actions` `share` rule (`mode = "attachment-route"`) between `shared` and `prod`.
- **Optional AWS RAM Share** (`enable_ram_share = false` by default): only needed if you want to share the core network with a second AWS account. Per AWS documentation, a global core network resource must be shared from `us-east-1`.

## Official AWS Documentation Sources

- What is AWS Cloud WAN: https://docs.aws.amazon.com/network-manager/latest/cloudwan/what-is-cloudwan.html
- Core network policy versions: https://docs.aws.amazon.com/network-manager/latest/cloudwan/cloudwan-create-policy-version.html
- Core network policy version parameters (JSON): https://docs.aws.amazon.com/network-manager/latest/cloudwan/cloudwan-policies-json.html
- Attachments in AWS Cloud WAN: https://docs.aws.amazon.com/network-manager/latest/cloudwan/cloudwan-create-attachment.html
- Shared AWS Cloud WAN core network (RAM): https://docs.aws.amazon.com/network-manager/latest/cloudwan/cloudwan-share-network.html
- AWS Cloud WAN Quotas: https://docs.aws.amazon.com/network-manager/latest/cloudwan/cloudwan-quotas.html
- AWS Cloud WAN Pricing: https://aws.amazon.com/cloud-wan/pricing/

## Prerequisites

- Terraform `>= 1.5.0`
- AWS CLI v2 configured with credentials that can manage `networkmanager`, `ec2`, and (if enabled) `ram`
- An AWS account where you have permission to create and delete VPCs and Cloud WAN resources

## Step 1: Deploy Isolated Segments (Blocked Sharing)

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Note the outputs: `global_network_id`, `core_network_id`, `prod_attachment_id`, and `shared_attachment_id`.

## Step 2: Verify Isolated State via AWS CLI

Set shell variables from Terraform outputs:

```bash
GLOBAL_NET_ID=$(terraform output -raw global_network_id)
CORE_NET_ID=$(terraform output -raw core_network_id)
```

1. **List attachments and confirm segment placement:**

```bash
aws networkmanager list-attachments \
  --core-network-id "$CORE_NET_ID" \
  --query "Attachments[].{Id:AttachmentId,Type:AttachmentType,Segment:SegmentName,State:State}" \
  --output table
```

2. **Check policy versions and confirm the `LIVE` policy:**

```bash
aws networkmanager list-core-network-policy-versions \
  --core-network-id "$CORE_NET_ID" \
  --output table

aws networkmanager get-core-network-policy \
  --core-network-id "$CORE_NET_ID" \
  --alias LIVE
```

3. **Inspect `prod` segment routes (isolated — should show only `10.10.0.0/16`, not `10.20.0.0/16`):**

```bash
aws networkmanager get-network-routes \
  --global-network-id "$GLOBAL_NET_ID" \
  --route-table-identifier "{\"CoreNetworkSegmentEdge\":{\"CoreNetworkId\":\"$CORE_NET_ID\",\"SegmentName\":\"prod\",\"EdgeLocation\":\"us-east-1\"}}"
```

## Step 3: Allow Segment Sharing (Terraform or AWS CLI)

### Option A: Using Terraform

```bash
terraform apply -var="allow_prod_shared_sharing=true"
```

### Option B: Using AWS CLI (`put` -> `get-change-set` -> `execute`)

```bash
# 1. Upload a new policy version with segment-actions share enabled
aws networkmanager put-core-network-policy \
  --core-network-id "$CORE_NET_ID" \
  --policy-document file://policy-allow.json \
  --description "Allow shared and prod segment sharing"

# 2. Check the new policy version ID (for example, 3) and inspect its change set
aws networkmanager list-core-network-policy-versions \
  --core-network-id "$CORE_NET_ID" \
  --output table

aws networkmanager get-core-network-change-set \
  --core-network-id "$CORE_NET_ID" \
  --policy-version-id 3

# 3. Execute the change set to promote it to LIVE
aws networkmanager execute-core-network-change-set \
  --core-network-id "$CORE_NET_ID" \
  --policy-version-id 3
```

## Step 4: Re-Verify Segment Routes After Sharing

Run `get-network-routes` again for the `prod` segment in `us-east-1`:

```bash
aws networkmanager get-network-routes \
  --global-network-id "$GLOBAL_NET_ID" \
  --route-table-identifier "{\"CoreNetworkSegmentEdge\":{\"CoreNetworkId\":\"$CORE_NET_ID\",\"SegmentName\":\"prod\",\"EdgeLocation\":\"us-east-1\"}}"
```

With the `share` action `LIVE`, `prod` now receives the `10.20.0.0/16` attachment route from `shared` (and `shared` receives `10.10.0.0/16` from `prod` because Cloud WAN segment sharing is bidirectional by default unless restricted with `deny-filter`).

To return to blocked isolation via AWS CLI, upload `policy-block.json` with `put-core-network-policy` and execute the resulting change set, or run `terraform apply -var="allow_prod_shared_sharing=false"`.

## Step 5: Teardown & Cost Cleanup (REQUIRED)

Delete all resources immediately when finished so Cloud WAN stops billing:

```bash
terraform destroy
```

Wait for `terraform destroy` to finish (Cloud WAN attachments and core networks can take 10–20 minutes to delete). Then verify nothing remains:

```bash
aws networkmanager list-attachments --core-network-id "$CORE_NET_ID"
aws networkmanager list-core-networks
aws networkmanager describe-global-networks
```

Confirm that your lab core network, VPC attachments, and global network are gone before closing your session.
