# Run these resources from your AWS Firewall Manager administrator account
# after completing the official AWS Organizations and AWS Config prerequisites.
# Note: This lab intentionally omits AWS Shield Advanced so you do not incur
# a paid Shield Advanced subscription.

# -----------------------------------------------------------------------------
# 1. Primary Security Group (Admin Account) + Common Security Group Policy
# -----------------------------------------------------------------------------
resource "aws_security_group" "primary_https_baseline" {
  count       = var.create_example_common_sg_policy ? 1 : 0
  name        = "${var.policy_name_prefix}-primary-https-sg"
  description = "Primary baseline security group replicated by AWS Firewall Manager"
  vpc_id      = var.admin_primary_sg_vpc_id

  ingress {
    description = "Allow HTTPS inbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.policy_name_prefix}-primary-https-sg"
    Lab     = "2026-11-26-aws-firewall-manager"
    Managed = "Terraform"
  }
}

resource "aws_fms_policy" "common_sg_policy" {
  count                              = var.create_example_common_sg_policy ? 1 : 0
  name                               = "${var.policy_name_prefix}-common-sg"
  delete_all_policy_resources        = var.delete_all_policy_resources_on_destroy
  delete_unused_fm_managed_resources = var.delete_unused_fm_managed_resources
  exclude_resource_tags              = true
  remediation_enabled                = var.remediation_enabled
  resource_type_list                 = ["AWS::ElasticLoadBalancingV2::LoadBalancer"]

  resource_tags = {
    (var.exclude_tag_key) = var.exclude_tag_value
  }

  include_map {
    orgunit = var.in_scope_ou_ids
  }

  dynamic "exclude_map" {
    for_each = length(var.excluded_account_ids) > 0 ? [1] : []
    content {
      account = var.excluded_account_ids
    }
  }

  security_service_policy_data {
    type = "SECURITY_GROUPS_COMMON"

    managed_service_data = jsonencode({
      type = "SECURITY_GROUPS_COMMON"
      securityGroups = [
        {
          id = aws_security_group.primary_https_baseline[0].id
        }
      ]
      revertManualSecurityGroupChanges = true
      exclusiveResourceSecurityGroupManagement = false
      applyToAllEC2InstanceENIs        = false
      includeSharedVPC                 = false
    })
  }
}

# -----------------------------------------------------------------------------
# 2. Org-Wide AWS WAFv2 Policy for Application Load Balancers
# -----------------------------------------------------------------------------
resource "aws_fms_policy" "alb_wafv2_policy" {
  count                              = var.create_example_waf_policy ? 1 : 0
  name                               = "${var.policy_name_prefix}-alb-wafv2"
  delete_all_policy_resources        = var.delete_all_policy_resources_on_destroy
  delete_unused_fm_managed_resources = var.delete_unused_fm_managed_resources
  exclude_resource_tags              = true
  remediation_enabled                = var.remediation_enabled
  resource_type                      = "AWS::ElasticLoadBalancingV2::LoadBalancer"

  resource_tags = {
    (var.exclude_tag_key) = var.exclude_tag_value
  }

  include_map {
    orgunit = var.in_scope_ou_ids
  }

  dynamic "exclude_map" {
    for_each = length(var.excluded_account_ids) > 0 ? [1] : []
    content {
      account = var.excluded_account_ids
    }
  }

  security_service_policy_data {
    type = "WAFV2"

    managed_service_data = jsonencode({
      type = "WAFV2"
      preProcessRuleGroups = [
        {
          ruleGroupArn  = null
          overrideAction = {
            type = "NONE"
          }
          managedRuleGroupIdentifier = {
            vendorName     = "AWS"
            managedRuleGroupName = "AWSManagedRulesCommonRuleSet"
            version        = null
          }
          ruleGroupType       = "ManagedRuleGroup"
          excludeRules        = []
          sampledRequestsEnabled = true
        }
      ]
      postProcessRuleGroups = []
      defaultAction = {
        type = "ALLOW"
      }
      overrideCustomerWebACLAssociation = false
      loggingConfiguration              = null
    })
  }
}
