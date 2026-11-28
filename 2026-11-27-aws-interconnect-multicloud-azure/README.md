# AWS Interconnect - Multicloud with Microsoft Azure: Terraform & AWS CLI Lab

> **COST WARNING:** An AWS Interconnect, Direct Connect gateway attachments, Transit Gateway attachments, and any Azure-side resources **bill continuously until they are deleted**. By default, this lab **does not** create an Interconnect. You must explicitly opt in before running any AWS CLI `create-connection` or `accept-connection-proposal` command, and you must follow the **Teardown / Destroy** steps at the end of this README to stop billing.
>
> Note: AWS offers one free, local (Tier 1) 500 Mbps Interconnect per AWS Region per Generally Available CSP on the AWS side, while the other CSP determines its own pricing independently. Always review both AWS and Azure pricing before provisioning.

## What This Lab Builds

### 1. AWS Foundation (Terraform in `lab/`)
- **AWS VPC** (`10.10.0.0/16`) and private subnet (`10.10.1.0/24`) — non-overlapping with Azure VNet (`10.20.0.0/16`).
- **Transit Gateway** (local to `us-east-1`, `eu-central-1`, or `ap-southeast-2`) + VPC attachment + route to `10.20.0.0/16`.
- **Direct Connect gateway** (the required AWS attach point for AWS Interconnect).
- **Transit Gateway to Direct Connect gateway association** with `allowed_prefixes = ["10.10.0.0/16"]`.
- **CloudWatch Alarm** on `AWS/Interconnect` `ConnectionUtilizationEgress` (created once you provide `interconnect_connection_id`).

### 2. Optional Azure Virtual Network (Terraform in `lab/azure-optional/`)
- Resource group, Azure VNet (`10.20.0.0/16`), `workload-subnet` (`10.20.1.0/24`), and `GatewaySubnet` (`10.20.255.0/27`).

### 3. AWS Interconnect Create / Accept (AWS CLI or Console — Provider Gap Note)
As of November 28, 2026, the Terraform `hashicorp/aws` provider pull requests for AWS Interconnect are **still open and not merged**:
- PR #48265: `aws_interconnect_connection` (open)
- PR #49637: `aws_interconnect_connection_proposal_acceptor` (open)

Therefore, this lab provisions the AWS networking foundation with Terraform and creates or accepts the Interconnect object using the **AWS CLI** (`aws interconnect ...`) or the **AWS Direct Connect Console**.

---

## Supported GA Region Pairs (AWS ↔ Microsoft Azure)

| AWS Region | Azure Region |
| --- | --- |
| `us-east-1` (N. Virginia) | `eastus` (US East) |
| `eu-central-1` (Frankfurt) | `germanywestcentral` (Germany West Central) |
| `ap-southeast-2` (Sydney) | `australiaeast` (Australia East) |

---

## Step 1 — Deploy the AWS Foundation (Terraform)

```bash
cd lab
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Capture the Direct Connect gateway ID from Terraform output:

```bash
DXGW_ID=$(terraform output -raw direct_connect_gateway_id)
echo "$DXGW_ID"
```

*(Optional)* Deploy the Azure VNet in `lab/azure-optional/`:

```bash
cd azure-optional
terraform init
terraform plan
terraform apply
```

---

## Step 2 — Opt In and Create or Accept the Interconnect (AWS CLI)

> **Explicit Opt-In Required:** Only run these commands if you accept the hourly charges on AWS and Microsoft Azure.

### Option A: Start from AWS (`create-connection`)

1. List available environments in your local AWS Region to find the Microsoft Azure `environmentId`:

```bash
aws interconnect list-environments --region us-east-1
```

2. Create the Interconnect attached to your Direct Connect gateway:

```bash
aws interconnect create-connection \
  --region us-east-1 \
  --description "aws-ic-azure-lab" \
  --bandwidth "1Gbps" \
  --attach-point "directConnectGateway=${DXGW_ID}" \
  --environment-id "<AZURE_ENVIRONMENT_ID>" \
  --remote-account "identifier=<YOUR_AZURE_ACCOUNT_IDENTIFIER>"
```

3. Copy the returned **Activation Key** and complete activation in the **Azure Portal** (Azure Multicloud Interconnect).

### Option B: Start from Azure (`accept-connection-proposal`)

If you initiated the Interconnect in the Azure Portal and received an Activation Key:

```bash
aws interconnect accept-connection-proposal \
  --region us-east-1 \
  --attach-point "directConnectGateway=${DXGW_ID}" \
  --activation-key "<ACTIVATION_KEY_FROM_AZURE>" \
  --description "aws-ic-azure-lab"
```

---

## Step 3 — Verify and Enable the CloudWatch Utilization Alarm

Check the connection status:

```bash
aws interconnect list-connections --region us-east-1
aws interconnect get-connection --region us-east-1 --identifier "<CONNECTION_ID>"
```

Scale bandwidth in place without reprovisioning (example):

```bash
aws interconnect update-connection \
  --region us-east-1 \
  --identifier "<CONNECTION_ID>" \
  --bandwidth "2Gbps"
```

Once active, set `interconnect_connection_id = "<CONNECTION_ID>"` in `terraform.tfvars` and run `terraform apply` to create the `ConnectionUtilizationEgress` CloudWatch alarm. Also open **CloudWatch Network Synthetic Monitor** in the AWS Console to review the included free latency and packet loss probe (note: Network Health Indicator is not yet supported on Interconnects).

---

## Step 4 — Teardown / Destroy Everything (Stop Billing!)

Follow this order so AWS does not block Direct Connect gateway deletion:

1. **Delete the AWS Interconnect connection first:**

```bash
aws interconnect delete-connection \
  --region us-east-1 \
  --identifier "<CONNECTION_ID>"
```

2. **Delete the corresponding Azure Multicloud Interconnect resource** in the Azure Portal (AWS notifies the partner, but Azure may still require explicit cleanup).

3. **Destroy the AWS Terraform stack:**

```bash
cd lab
terraform destroy
```

4. *(If deployed)* **Destroy the optional Azure VNet stack:**

```bash
cd lab/azure-optional
terraform destroy
```

---

## Official Sources

- AWS What's New (Nov 17, 2026): https://aws.amazon.com/about-aws/whats-new/2026/11/aws-announces-AWS-interconnect-multicloud-azure-ga/
- AWS Interconnect User Guide: https://docs.aws.amazon.com/interconnect/latest/userguide/what-is.html
- AWS CLI `interconnect` Reference: https://awscli.amazonaws.com/v2/documentation/api/latest/reference/interconnect/index.html
- Microsoft Azure Networking Blog (Nov 17, 2026): https://techcommunity.microsoft.com/blog/azurenetworkingblog/connecting-clouds-and-the-last-mile-with-azure/4573283
- Azure Updates (Nov 17, 2026): https://mc.merill.net/message/AZ579766
