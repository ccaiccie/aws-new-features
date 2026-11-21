# PROVIDER GAP (read README.md): hashicorp/aws 6.73.0 has aws_networksecuritymanager_* resources, but
#   * aws_networksecuritymanager_policy has no igw_firewall_config block (DefaultSubnetConnectivity,
#     SubnetConnectivityOverrides) - only waf_config, and
#   * aws_networksecuritymanager_scope has no specialized_scope_type (needed for a subnet connectivity override).
# Open requests: hashicorp/terraform-provider-aws #51208 and #51209 (automated Internet firewall support).
# CloudFormation documents every piece (AWS::NetworkSecurityManager::Rule, Template, Policy, Scope, Deployment
# with FirewallType IGW_FIREWALL), so Terraform deploys them through a real aws_cloudformation_stack.
# Replace this stack with native resources when the provider catches up.
#
# You never create the firewall itself: the Deployment makes NSM build one igw-firewall per in-scope VPC,
# named arn:aws:network-firewall:<region>:<account>:igw-firewall/<vpc-id>, read-only in Network Firewall.

locals {
  vpc_scope_config = merge(
    var.multi_account ? { AccountFilter = { IncludeAll = true } } : {},
    {
      ResourceScopes = {
        "AWS::EC2::VPC" = {
          Include = { Expression = { Criteria = { Tags = { "internet-inspection" = "enabled" } } } }
        }
      }
    }
  )

  isolated_scope_config = {
    ResourceScopes = {
      "AWS::EC2::Subnet" = {
        Include = { Expression = { Criteria = { Tags = { "network-zone" = "isolated" } } } }
      }
    }
  }

  # Optional IPS rule-group rules (one setting per NSM rule).
  ips_rules = {
    for i, arn in var.managed_ips_rule_group_arns : "IpsRule${i}" => {
      Type = "AWS::NetworkSecurityManager::Rule"
      Properties = {
        RuleName        = "${var.name}-ips-${i}"
        RuleDescription = "IPS rule group entry ${i}"
        FirewallType    = "IGW_FIREWALL"
        RuleType        = "INSPECTION"
        Configuration   = jsonencode({ IpsRuleGroupEntry = { ResourceArn = arn } })
      }
    }
  }

  nsm_template = {
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Automated internet firewall: NSM rule, template, policy, scopes and deployment (Terraform lab)"
    Resources = merge(local.ips_rules, {
      ModeRule = {
        Type = "AWS::NetworkSecurityManager::Rule"
        Properties = {
          RuleName        = "${var.name}-mode"
          RuleDescription = "Sets the internet firewall policy mode"
          FirewallType    = "IGW_FIREWALL"
          RuleType        = "INSPECTION"
          Configuration   = jsonencode({ PolicyMode = var.policy_mode })
        }
      }
      LabTemplate = {
        Type = "AWS::NetworkSecurityManager::Template"
        Properties = {
          TemplateName = "${var.name}-template"
          FirewallType = "IGW_FIREWALL"
          AssociatedRuleList = concat(
            [{ RuleArn = { "Fn::GetAtt" = ["ModeRule", "RuleArn"] } }],
            [for k in keys(local.ips_rules) : { RuleArn = { "Fn::GetAtt" = [k, "RuleArn"] } }]
          )
        }
      }
      IsolatedSubnetsScope = {
        Type = "AWS::NetworkSecurityManager::Scope"
        Properties = {
          ScopeName            = "${var.name}-isolated-subnets"
          SpecializedScopeType = "IGW_FIREWALL_SUBNET_CONNECTIVITY_OVERRIDE"
          ScopeConfiguration   = jsonencode(local.isolated_scope_config)
        }
      }
      InternetFirewallPolicy = {
        Type = "AWS::NetworkSecurityManager::Policy"
        Properties = {
          PolicyName                    = "${var.name}-policy"
          PolicyDescription             = "Inspects IGW traffic; flexible connectivity; isolated subnets excluded"
          FirewallType                  = "IGW_FIREWALL"
          Priority                      = var.policy_priority
          AssociatedTemplateAndRuleList = [{ TemplateArn = { "Fn::GetAtt" = ["LabTemplate", "TemplateArn"] } }]
          PolicyConfiguration = {
            RemediationEnabled = true # required for automated internet firewall policies
            ResourcesCleanUp   = true
            IgwFirewallConfig = {
              DefaultSubnetConnectivity = var.default_subnet_connectivity
              SubnetConnectivityOverrides = [{
                ConnectivityType = "exclude"
                Scopes           = [{ "Fn::GetAtt" = ["IsolatedSubnetsScope", "ScopeArn"] }]
              }]
            }
          }
        }
      }
      InspectedVpcsScope = {
        Type = "AWS::NetworkSecurityManager::Scope"
        Properties = {
          ScopeName          = "${var.name}-vpcs"
          ScopeConfiguration = jsonencode(local.vpc_scope_config)
        }
      }
      InternetFirewallDeployment = {
        Type = "AWS::NetworkSecurityManager::Deployment"
        Properties = {
          DeploymentName        = "${var.name}-deployment"
          DeploymentDescription = "Applies the lab internet firewall policy to VPCs tagged internet-inspection = enabled"
          AssociatedPolicyList  = [{ PolicyArn = { "Fn::GetAtt" = ["InternetFirewallPolicy", "PolicyArn"] } }]
          AssociatedScopeList   = [{ ScopeArn = { "Fn::GetAtt" = ["InspectedVpcsScope", "ScopeArn"] } }]
        }
      }
    })
    Outputs = {
      PolicyArn     = { Value = { "Fn::GetAtt" = ["InternetFirewallPolicy", "PolicyArn"] } }
      DeploymentArn = { Value = { "Fn::GetAtt" = ["InternetFirewallDeployment", "DeploymentArn"] } }
    }
  }
}

resource "aws_cloudformation_stack" "nsm" {
  name          = "${var.name}-nsm"
  template_body = jsonencode(local.nsm_template)

  # Build the subnets (with their tags) and the instances first, so the firewall has an
  # active network interface in the AZ and the isolated subnet is already tagged for exclusion.
  depends_on = [
    aws_route_table_association.public,
    aws_route_table_association.private,
    aws_route_table_association.isolated,
    aws_instance.public,
    aws_instance.private,
  ]

  timeouts {
    create = "30m"
    delete = "30m"
  }
}
