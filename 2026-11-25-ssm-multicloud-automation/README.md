# AWS Systems Manager Automation for Microsoft Azure and Google Cloud — Terraform Practice Lab

Companion Terraform practice lab for the Network Technician lesson on **AWS Systems Manager Automation for Microsoft Azure and Google Cloud** (announced November 23, 2026).

## What This Lab Creates

Using the official `hashicorp/aws` provider (`v6.74.0` locked in `.terraform.lock.hcl`), this lab creates:

1. **Automation Assume Roles** (`aws_iam_role` + `aws_iam_role_policy`):
   - `SSM-AzureAssumeRole-<slug>-<connector-prefix>` in path `/service-role/` with tag `caller=SSM`
   - `SSM-GCPAssumeRole-<slug>-<connector-prefix>` in path `/service-role/` with tag `caller=SSM`
   - Both roles trust `ssm.amazonaws.com` scoped with `aws:SourceAccount`, and grant `sts:AssumeRole` on the connector's IAM federation role, `ssm:GetCloudConnector` on the connector, and `iam:ListRoleTags` on themselves.
2. **Three Real Multicloud Automation Runbooks** (`aws_ssm_document`, `document_type = "Automation"`, `document_format = "YAML"`):
   - **`NT-MulticloudLab-AzureAssertVmRunning`**: Parses an Azure VM resource ID and uses the no-code `aws:assertAzureResourceProperty` action (`Package: azure_202610`) to verify `PowerState/running`.
   - **`NT-MulticloudLab-GcpStartAndWaitVm`**: Parses a Google Cloud instance ID, calls `aws:executeGcpApi` (`Instances.Start`), and polls with `aws:waitForGcpResourceProperty` (`Package: gcp_202610`) until `$.status` is `RUNNING`.
   - **`NT-MulticloudLab-AzureSdkInspectVm`**: Uses `aws:executeScript` (`Runtime: python3.11`, `Package: azure_202610`) with the preinstalled `azure.mgmt.compute` SDK and short-lived `AZURE_ACCESS_TOKEN` injected from the Cloud Connector—zero stored secrets.

## Honest Provider Gaps (As of `hashicorp/aws` v6.74.0)

The current `hashicorp/aws` provider does **not** yet include a dedicated resource for creating or managing a **Systems Manager Cloud Connector** (no `aws_ssm_cloud_connector` resource exists). Additionally, setting the `cloudProviders` metadata (`Azure` or `GCP`) on an Automation document so it appears under the console's *Hybrid and multicloud* filter may require the AWS Console or AWS CLI depending on your provider version.

Create the Cloud Connector first in the AWS Console (or via AWS CLI) in the **same AWS Region** where you apply this Terraform lab:

1. **Create a Cloud Connector** in the AWS Systems Manager console under **Hybrid and Multicloud nodes** (available in all AWS Regions where you can create a Systems Manager Cloud Connector).
   - For Microsoft Azure: follow [Set up a Cloud Connector for Microsoft Azure in Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-cloud-connector.html).
   - For Google Cloud: follow [Set up a Cloud Connector for Google Cloud Platform in Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-cloud-connector-gcp.html).
2. **Fetch the connector's IAM federation role ARN** via AWS CLI (in the same AWS Region as the connector):
   ```bash
   aws ssm get-cloud-connector \
     --region us-east-1 \
     --cloud-connector-id <your-connector-id> \
     --query RoleArn \
     --output text
   ```
3. **Grant required permissions in Azure or Google Cloud**:
   - The default connector setup grants read access for discovery. For write actions such as starting/stopping VMs (`compute.instances.start` in GCP or Virtual Machine Contributor / custom stop role in Azure), grant the connector's Azure identity or Google Cloud service account the corresponding role in that cloud.

## Prerequisites

- Terraform `>= 1.6.0`
- AWS CLI v2 configured with credentials for your target AWS account
- An existing Systems Manager Cloud Connector for Microsoft Azure and/or Google Cloud in the same AWS Region (`var.aws_region`)
- Note: A Cloud Connector is regional. Always apply and run automations in the same AWS Region where the connector was created.

## Apply

Create a local `terraform.tfvars` (ignored by `.gitignore`) with your real connector IDs and federation role ARNs, or run with placeholders first to inspect the generated roles and runbooks:

```hcl
aws_region                = "us-east-1"
connector_name_slug       = "MyConnector"
azure_cloud_connector_id  = "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
azure_federation_role_arn = "arn:aws:iam::111122223333:role/..."
gcp_cloud_connector_id    = "b2c3d4e5-6789-01bc-def0-EXAMPLE22222"
gcp_federation_role_arn   = "arn:aws:iam::111122223333:role/..."
```

Initialize, validate, and apply:

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

## Verify & Run an Automation

1. Confirm the IAM roles and Automation runbooks exist in your Region:
   ```bash
   aws ssm list-documents \
     --region us-east-1 \
     --filters Key=Owner,Values=Self Key=DocumentType,Values=Automation
   ```
2. Update `examples/start-azure.json` or `examples/start-gcp.json` with your AWS account ID, connector ID, and target filters (`AzureSubscriptions`, `CloudProviderRegions`, `AzureResourceGroups`, `AzureTag` for Azure; `GcpProjects`, `Zones`, `IncludesLabels` for Google Cloud).
3. Start a rate-controlled automation with a Cloud Connector target:
   ```bash
   aws ssm start-automation-execution \
     --region us-east-1 \
     --cli-input-json file://examples/start-azure.json
   ```
4. Inspect the parent execution and child automations:
   ```bash
   aws ssm describe-automation-executions \
     --region us-east-1 \
     --filters Key=ParentExecutionId,Values=<parent-execution-id>

   aws ssm get-automation-execution \
     --region us-east-1 \
     --automation-execution-id <parent-execution-id>
   ```

> **Note on Execution Modes:** Rate control with `Parameter Values` supports up to 50 VMs—use a `CloudConnector` target for larger fleets. Multi-account and Region execution does not support Cloud Connector targets. API actions and `aws:executeScript` steps do not require SSM Agent on target VMs.

## Cost Notes

- **IAM roles and custom Systems Manager Automation documents**: No recurring monthly fee for storing IAM roles or SSM documents.
- **Systems Manager Automation executions**: AWS Systems Manager Automation provides a free tier of basic steps per month per account, after which per-step charges apply according to current AWS Systems Manager pricing.
- **Azure / Google Cloud API calls**: Starting or running VMs in Azure or Google Cloud incurs standard compute charges in those clouds.

## Cleanup

Destroy all Terraform-managed IAM roles and Automation documents when finished:

```bash
terraform destroy
```

If you also created a Cloud Connector in the AWS Console solely for testing, delete it from **Systems Manager → Hybrid and Multicloud nodes** (and remove the federated app/workload identity configuration in Azure or Google Cloud).

## Official References

- [AWS What's New: AWS Systems Manager Automation now automates operational tasks in Azure and Google Cloud](https://aws.amazon.com/about-aws/whats-new/2026/11/systems-manager-multicloud-automation/)
- [Run automations on multicloud resources](https://docs.aws.amazon.com/systems-manager/latest/userguide/running-automations-cloud-connector.html)
- [Create runbooks that call Azure and Google Cloud APIs](https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-multicloud-runbooks.html)
