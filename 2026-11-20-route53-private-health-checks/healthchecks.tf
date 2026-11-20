# PROVIDER GAP: hashicorp/aws 6.73.0 has no resource for a Route 53 health check
# source, and aws_route53_health_check has no endpoint_type / health_check_source_id
# arguments yet (requests: hashicorp/terraform-provider-aws issues #51152 and #51153).
# CloudFormation documents both AWS::Route53::HealthCheckSource and the new
# EndpointType / HealthCheckSourceId properties of AWS::Route53::HealthCheck,
# so Terraform deploys them through a real aws_cloudformation_stack.
# When the provider adds native support, replace this stack with native resources.

locals {
  hc_template = {
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Route 53 health check source + two private endpoint health checks (Terraform lab)"
    Resources = {
      Source = {
        Type = "AWS::Route53::HealthCheckSource"
        Properties = {
          HealthCheckSourceConfig = {
            VpcId = aws_vpc.lab.id
            SubnetConfigurationList = [for i in range(3) : {
              SubnetId            = aws_subnet.private[i].id
              AvailabilityZoneId  = local.az_ids[i] # AZ ID (use1-az1), not the AZ name
              SecurityGroupIdList = [aws_security_group.hc_source.id]
            }]
          }
          Tags = [{ Key = "Name", Value = "${var.name}-source" }]
        }
      }
      PrimaryCheck = {
        Type = "AWS::Route53::HealthCheck"
        Properties = {
          HealthCheckConfig = {
            Type                = "HTTP"
            EndpointType        = "PRIVATE"
            HealthCheckSourceId = { "Fn::GetAtt" = ["Source", "HealthCheckSourceId"] }
            IPAddress           = local.primary
            Port                = var.app_port
            ResourcePath        = var.health_path
            RequestInterval     = var.request_interval
            FailureThreshold    = var.failure_threshold
          }
          HealthCheckTags = [{ Key = "Name", Value = "${var.name}-primary" }]
        }
      }
      SecondaryCheck = {
        Type = "AWS::Route53::HealthCheck"
        Properties = {
          HealthCheckConfig = {
            Type                = "HTTP"
            EndpointType        = "PRIVATE"
            HealthCheckSourceId = { "Fn::GetAtt" = ["Source", "HealthCheckSourceId"] }
            IPAddress           = local.standby
            Port                = var.app_port
            ResourcePath        = var.health_path
            RequestInterval     = var.request_interval
            FailureThreshold    = var.failure_threshold
          }
          HealthCheckTags = [{ Key = "Name", Value = "${var.name}-secondary" }]
        }
      }
    }
    Outputs = {
      HealthCheckSourceId = { Value = { "Fn::GetAtt" = ["Source", "HealthCheckSourceId"] } }
      PrimaryCheckId      = { Value = { Ref = "PrimaryCheck" } }
      SecondaryCheckId    = { Value = { Ref = "SecondaryCheck" } }
    }
  }
}

resource "aws_cloudformation_stack" "private_health_checks" {
  name          = "${var.name}-health-checks"
  template_body = jsonencode(local.hc_template)

  # The ENIs come from the service-linked role AWSServiceRoleForRoute53PrivateHealthChecks.
  # The identity running terraform needs iam:CreateServiceLinkedRole
  # (iam:AWSServiceName = route53healthchecks.amazonaws.com) on every create AND delete.
  depends_on = [
    aws_vpc_security_group_egress_rule.hc_source_to_app,
    aws_vpc_security_group_ingress_rule.app_from_hc_source,
    aws_instance.web,
  ]

  timeouts {
    create = "30m"
    delete = "30m"
  }
}
