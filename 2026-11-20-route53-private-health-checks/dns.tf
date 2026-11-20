# Private hosted zone with an active-passive failover pair.
# Both checks are same-account (cross-account association isn't supported).

resource "aws_route53_zone" "lab" {
  name    = var.zone_name
  comment = "Route 53 private endpoint health check lab"

  vpc {
    vpc_id = aws_vpc.lab.id
  }
}

resource "aws_route53_record" "primary" {
  zone_id         = aws_route53_zone.lab.zone_id
  name            = local.app_fqdn
  type            = "A"
  ttl             = 10
  records         = [local.primary]
  set_identifier  = "primary"
  health_check_id = aws_cloudformation_stack.private_health_checks.outputs["PrimaryCheckId"]

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "secondary" {
  zone_id         = aws_route53_zone.lab.zone_id
  name            = local.app_fqdn
  type            = "A"
  ttl             = 10
  records         = [local.standby]
  set_identifier  = "secondary"
  health_check_id = aws_cloudformation_stack.private_health_checks.outputs["SecondaryCheckId"]

  failover_routing_policy {
    type = "SECONDARY"
  }
}
