data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  partition       = data.aws_partition.current.partition
  azure_id_prefix = substr(var.azure_cloud_connector_id, 0, 8)
  gcp_id_prefix   = substr(var.gcp_cloud_connector_id, 0, 8)
  azure_role_name = "SSM-AzureAssumeRole-${var.connector_name_slug}-${local.azure_id_prefix}"
  gcp_role_name   = "SSM-GCPAssumeRole-${var.connector_name_slug}-${local.gcp_id_prefix}"
  azure_fed_arn   = var.azure_federation_role_arn != "" ? var.azure_federation_role_arn : "arn:${local.partition}:iam::${local.account_id}:role/*"
  gcp_fed_arn     = var.gcp_federation_role_arn != "" ? var.gcp_federation_role_arn : "arn:${local.partition}:iam::${local.account_id}:role/*"
  azure_conn_arn  = "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:cloudconnector/${var.azure_cloud_connector_id}"
  gcp_conn_arn    = "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:cloudconnector/${var.gcp_cloud_connector_id}"
}

# ------------------------------------------------------------------------------
# Trust policy for Systems Manager Automation Assume Roles
# Scoped to the current AWS account via aws:SourceAccount
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "ssm_automation_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Automation Assume Role for Microsoft Azure Cloud Connector
# Must be in /service-role/, start with SSM-AzureAssumeRole, and carry tag caller=SSM
# Keep tags minimal so federation token size stays small.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "azure_automation_assume" {
  name               = local.azure_role_name
  path               = "/service-role/"
  assume_role_policy = data.aws_iam_policy_document.ssm_automation_trust.json
  description        = "Automation assume role for AWS Systems Manager multicloud runbooks targeting Microsoft Azure."

  tags = {
    caller = "SSM"
  }
}

data "aws_iam_policy_document" "azure_automation_permissions" {
  statement {
    sid       = "AssumeConnectorFederationRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [local.azure_fed_arn]
  }

  statement {
    sid       = "ReadAzureCloudConnector"
    effect    = "Allow"
    actions   = ["ssm:GetCloudConnector"]
    resources = [local.azure_conn_arn]
  }

  statement {
    sid       = "ListOwnRoleTagsForFederationToken"
    effect    = "Allow"
    actions   = ["iam:ListRoleTags"]
    resources = [aws_iam_role.azure_automation_assume.arn]
  }
}

resource "aws_iam_role_policy" "azure_automation_permissions" {
  name   = "ssm-multicloud-azure-connector-access"
  role   = aws_iam_role.azure_automation_assume.id
  policy = data.aws_iam_policy_document.azure_automation_permissions.json
}

# ------------------------------------------------------------------------------
# 2. Automation Assume Role for Google Cloud Connector
# Must be in /service-role/, start with SSM-GCPAssumeRole, and carry tag caller=SSM
# ------------------------------------------------------------------------------
resource "aws_iam_role" "gcp_automation_assume" {
  name               = local.gcp_role_name
  path               = "/service-role/"
  assume_role_policy = data.aws_iam_policy_document.ssm_automation_trust.json
  description        = "Automation assume role for AWS Systems Manager multicloud runbooks targeting Google Cloud."

  tags = {
    caller = "SSM"
  }
}

data "aws_iam_policy_document" "gcp_automation_permissions" {
  statement {
    sid       = "AssumeConnectorFederationRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [local.gcp_fed_arn]
  }

  statement {
    sid       = "ReadGcpCloudConnector"
    effect    = "Allow"
    actions   = ["ssm:GetCloudConnector"]
    resources = [local.gcp_conn_arn]
  }

  statement {
    sid       = "ListOwnRoleTagsForFederationToken"
    effect    = "Allow"
    actions   = ["iam:ListRoleTags"]
    resources = [aws_iam_role.gcp_automation_assume.arn]
  }
}

resource "aws_iam_role_policy" "gcp_automation_permissions" {
  name   = "ssm-multicloud-gcp-connector-access"
  role   = aws_iam_role.gcp_automation_assume.id
  policy = data.aws_iam_policy_document.gcp_automation_permissions.json
}

# ------------------------------------------------------------------------------
# 3. Custom Automation Runbook (No-Code Azure API Actions)
# Checks that an Azure VM is running using aws:assertAzureResourceProperty
# ------------------------------------------------------------------------------
resource "aws_ssm_document" "azure_assert_vm_running" {
  name            = "${var.name_prefix}-AzureAssertVmRunning"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<-YAML
    description: Checks that a Microsoft Azure VM is running using aws:assertAzureResourceProperty.
    schemaVersion: '0.3'
    assumeRole: '{{ AutomationAssumeRole }}'
    parameters:
      AutomationAssumeRole:
        type: AWS::IAM::Role::Arn
        description: The role that Automation assumes to run this runbook.
      CloudConnector:
        type: AWS::SSM::CloudConnector::Id
        description: The Systems Manager Cloud Connector that reaches the Azure VM.
      VmId:
        type: microsoft.Compute/VirtualMachines
        description: The Azure VM resource ID (passed automatically by a Cloud Connector target).
    mainSteps:
      - name: parseVmId
        action: aws:executeScript
        inputs:
          Runtime: python3.11
          Handler: parse_vm_id
          InputPayload:
            VmId: '{{ VmId }}'
          Script: |-
            def parse_vm_id(events, context):
                segments = events["VmId"].strip("/").split("/")
                parts = {segments[i].lower(): segments[i + 1] for i in range(0, len(segments) - 1, 2)}
                return {
                    "subscriptionId": parts["subscriptions"],
                    "resourceGroup": parts["resourcegroups"],
                    "vmName": parts["virtualmachines"],
                }
        outputs:
          - Name: SubscriptionId
            Selector: $.Payload.subscriptionId
            Type: String
          - Name: ResourceGroup
            Selector: $.Payload.resourceGroup
            Type: String
          - Name: VmName
            Selector: $.Payload.vmName
            Type: String
      - name: assertRunning
        action: aws:assertAzureResourceProperty
        inputs:
          Service: compute
          Api: VirtualMachines.Get
          Package: ${var.azure_sdk_package}
          CloudConnector: '{{ CloudConnector }}'
          SubscriptionId: '{{ parseVmId.SubscriptionId }}'
          resourceGroupName: '{{ parseVmId.ResourceGroup }}'
          vmName: '{{ parseVmId.VmName }}'
          expand: instanceView
          PropertySelector: $.properties.instanceView.statuses[1].code
          DesiredValues:
            - PowerState/running
  YAML
}

# ------------------------------------------------------------------------------
# 4. Custom Automation Runbook (No-Code Google Cloud API Actions)
# Starts a Google Cloud VM instance and waits until it reaches RUNNING
# ------------------------------------------------------------------------------
resource "aws_ssm_document" "gcp_start_and_wait_vm" {
  name            = "${var.name_prefix}-GcpStartAndWaitVm"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<-YAML
    description: Starts a Google Cloud VM instance with aws:executeGcpApi and waits with aws:waitForGcpResourceProperty.
    schemaVersion: '0.3'
    assumeRole: '{{ AutomationAssumeRole }}'
    parameters:
      AutomationAssumeRole:
        type: AWS::IAM::Role::Arn
        description: The role that Automation assumes to run this runbook.
      CloudConnector:
        type: AWS::SSM::CloudConnector::Id
        description: The Systems Manager Cloud Connector that reaches the Google Cloud instance.
      InstanceId:
        type: compute.googleapis.com/Instance
        description: The instance, as projects/PROJECT/zones/ZONE/instances/NAME.
    mainSteps:
      - name: parseInstanceId
        action: aws:executeScript
        inputs:
          Runtime: python3.11
          Handler: parse_instance_id
          InputPayload:
            InstanceId: '{{ InstanceId }}'
          Script: |-
            def parse_instance_id(events, context):
                name = events["InstanceId"].removeprefix("//compute.googleapis.com/").strip("/")
                segments = name.split("/")
                parts = {segments[i]: segments[i + 1] for i in range(0, len(segments) - 1, 2)}
                return {
                    "project": parts["projects"],
                    "zone": parts["zones"],
                    "instanceName": parts["instances"],
                }
        outputs:
          - Name: Project
            Selector: $.Payload.project
            Type: String
          - Name: Zone
            Selector: $.Payload.zone
            Type: String
          - Name: InstanceName
            Selector: $.Payload.instanceName
            Type: String
      - name: startInstance
        action: aws:executeGcpApi
        inputs:
          Service: compute
          Api: Instances.Start
          Package: ${var.gcp_sdk_package}
          CloudConnector: '{{ CloudConnector }}'
          project: '{{ parseInstanceId.Project }}'
          zone: '{{ parseInstanceId.Zone }}'
          instance: '{{ parseInstanceId.InstanceName }}'
      - name: waitForRunning
        action: aws:waitForGcpResourceProperty
        timeoutSeconds: 600
        inputs:
          Service: compute
          Api: Instances.Get
          Package: ${var.gcp_sdk_package}
          CloudConnector: '{{ CloudConnector }}'
          project: '{{ parseInstanceId.Project }}'
          zone: '{{ parseInstanceId.Zone }}'
          instance: '{{ parseInstanceId.InstanceName }}'
          PropertySelector: $.status
          DesiredValues:
            - RUNNING
  YAML
}

# ------------------------------------------------------------------------------
# 5. Custom Automation Runbook (aws:executeScript with Azure Python SDK)
# Uses short-lived AZURE_ACCESS_TOKEN from Cloud Connector; no stored secrets.
# ------------------------------------------------------------------------------
resource "aws_ssm_document" "azure_sdk_inspect_vm" {
  name            = "${var.name_prefix}-AzureSdkInspectVm"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<-YAML
    description: Inspects an Azure VM size and power state using aws:executeScript with the preinstalled Azure SDK for Python.
    schemaVersion: '0.3'
    assumeRole: '{{ AutomationAssumeRole }}'
    parameters:
      AutomationAssumeRole:
        type: AWS::IAM::Role::Arn
        description: The role that Automation assumes to run this runbook.
      CloudConnector:
        type: AWS::SSM::CloudConnector::Id
        description: The Systems Manager Cloud Connector that reaches the Azure VM.
      VmId:
        type: microsoft.Compute/VirtualMachines
        description: The Azure VM resource ID.
    mainSteps:
      - name: getPowerState
        action: aws:executeScript
        inputs:
          Runtime: python3.11
          Handler: get_power_state
          CloudConnector: '{{ CloudConnector }}'
          Package: ${var.azure_sdk_package}
          InputPayload:
            VmId: '{{ VmId }}'
          Script: |-
            import os
            import time
            from types import SimpleNamespace
            from azure.core.credentials import AccessToken
            from azure.mgmt.compute import ComputeManagementClient

            def parse_vm_id(vm_id):
                segments = vm_id.strip("/").split("/")
                parts = {segments[i].lower(): segments[i + 1] for i in range(0, len(segments) - 1, 2)}
                return parts["subscriptions"], parts["resourcegroups"], parts["virtualmachines"]

            def get_power_state(events, context):
                subscription_id, resource_group, vm_name = parse_vm_id(events["VmId"])
                token = AccessToken(os.environ["AZURE_ACCESS_TOKEN"], int(time.time()) + 600)
                credential = SimpleNamespace(get_token=lambda *scopes, **kwargs: token)
                with ComputeManagementClient(credential, subscription_id) as client:
                    vm = client.virtual_machines.get(resource_group, vm_name, expand="instanceView")
                power_state = "unknown"
                statuses = vm.instance_view.statuses if vm.instance_view else []
                for status in statuses or []:
                    if status.code and status.code.startswith("PowerState/"):
                        power_state = status.code.split("/", 1)[1]
                return {
                    "vmName": vm.name,
                    "location": vm.location,
                    "vmSize": vm.hardware_profile.vm_size,
                    "powerState": power_state,
                }
        outputs:
          - Name: VmSize
            Selector: $.Payload.vmSize
            Type: String
          - Name: PowerState
            Selector: $.Payload.powerState
            Type: String
  YAML
}
