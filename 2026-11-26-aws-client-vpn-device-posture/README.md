# Practice Lab: AWS Client VPN With Device Posture & Client Connect Handler

This compact Terraform and AWS CLI lab deploys an **AWS Client VPN endpoint** with CloudWatch connection logging, an **`AWSClientVPN-` client connect handler Lambda** (schema `v3`), and an official-style **Cedar device posture policy** you can test in shadow mode and then enforce.

Intended public repository path:
`https://github.com/ccaiccie/aws-new-features/tree/main/2026-11-26-aws-client-vpn-device-posture`

## Honest Note on Third-Party Trust Providers

AWS Client VPN device posture evaluates signed tokens generated on the endpoint device by a third-party trust provider (**CrowdStrike**, **Jamf**, or **JumpCloud**). AWS does not operate those providers. If you do not have a CrowdStrike, Jamf, or JumpCloud tenant in your lab account:
- You can still deploy the full VPC, Client VPN endpoint, CloudWatch connection logging, and the **client connect handler Lambda** (`AWSClientVPN-posture-lab-handler`) and test real allow/deny logic immediately.
- You can also inspect the official Cedar policy in `posture_policy.cedar` and run the official shadow-mode → enforce AWS CLI workflow once a trust provider is attached.

## What This Lab Deploys

1. **VPC & Private Subnet** (`10.60.0.0/16`, subnet `10.60.1.0/24`) with a dedicated security group.
2. **CloudWatch Logs Group & Stream** (`/aws/client-vpn/posture-lab`) for connection logging.
3. **Client Connect Handler Lambda** (`AWSClientVPN-posture-lab-handler`, Python 3.12, `lab/lambda/connect_handler.py`) returning official `v3` schema (`allow`, `error-msg-on-denied-connection`, `posture-compliance-statuses`, `schema-version`).
4. **AWS Client VPN Endpoint** (mutual authentication via your ACM certificate ARNs, client CIDR `10.61.0.0/22`, connection logging enabled, client connect handler enabled), **target network association**, and **authorization rule** granting access to `10.60.0.0/16`.
5. **Sample Cedar Policy** (`posture_policy.cedar`) using official CrowdStrike and Jamf attributes for shadow-mode testing and enforcement via AWS CLI.

## Prerequisites & Certificate Hygiene

- Terraform `>= 1.6` and AWS CLI v2 configured for your lab account and Region.
- Import a server certificate and client root CA certificate into **AWS Certificate Manager (ACM)** in the target Region (for example using Easy-RSA). **Never commit `.key`, `.pem`, `.crt`, or `terraform.tfvars` files to Git.**

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your ACM server_certificate_arn and client_root_certificate_arn

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

## Apply Cedar Policy in Shadow Mode → Enforce (AWS CLI)

Once a supported trust provider (`crowdstrike`, `jamf`, or `jumpcloud`) is configured on the endpoint under `DevicePostureOptions`:

```bash
EP_ID=$(terraform output -raw client_vpn_endpoint_id)

# Step 1: Attach Cedar policy in SHADOW MODE (evaluates & logs without blocking)
aws ec2 modify-client-vpn-endpoint-authorization-policy \
  --client-vpn-endpoint-id "$EP_ID" \
  --policy-document file://posture_policy.cedar \
  --description "Require CrowdStrike score > 50 and block jailbroken devices" \
  --shadow-mode enabled

# Step 2: Verify policy attachment
aws ec2 get-client-vpn-endpoint-authorization-policy \
  --client-vpn-endpoint-id "$EP_ID"

# Step 3: Inspect CloudWatch Logs (/aws/client-vpn/posture-lab) for authorization-policy-evaluation
aws logs filter-log-events \
  --log-group-name "$(terraform output -raw log_group_name)" \
  --filter-pattern "authorization-policy-evaluation"

# Step 4: Enforce (CAUTION: disconnects all active sessions on the endpoint!)
aws ec2 modify-client-vpn-endpoint-authorization-policy \
  --client-vpn-endpoint-id "$EP_ID" \
  --shadow-mode disabled
```

## Destroy & Clean Up (Stop Hourly Client VPN Charges!)

AWS Client VPN charges hourly for each target network association and active connection (plus CloudWatch Logs and Lambda invocations). Always destroy the lab when done:

```bash
terraform destroy
```

Confirm the endpoint is gone:
```bash
aws ec2 describe-client-vpn-endpoints --query "ClientVpnEndpoints[*].[ClientVpnEndpointId,Status.Code]"
```

## Official AWS Sources

- What is AWS Client VPN: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html
- Device posture for AWS Client VPN: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/device-posture.html
- How device posture works: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/device-posture-how-it-works.html
- Device posture concepts: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/device-posture-concepts.html
- Authoring device posture authorization policies: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/device-posture-policies.html
- Connection authorization / client connect handler: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/connection-authorization.html
- Connection logging: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/connection-logging.html
