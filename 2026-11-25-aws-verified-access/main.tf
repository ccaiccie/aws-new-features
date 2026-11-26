# AWS Verified Access — IAM Identity Center + Internal ALB + Cedar Policy Lab
# Official docs: https://docs.aws.amazon.com/verified-access/latest/ug/getting-started.html

locals {
  cedar_allow_policy = <<-EOT
    permit(principal, action, resource)
    when {
      context.${var.policy_reference_name}.groups has "${var.allowed_idc_group_id}"
      && context.${var.policy_reference_name}.user.email.verified == true
    };
  EOT
}

# Step 1: User-identity trust provider (AWS Organizations IAM Identity Center in same Region)
resource "aws_verifiedaccess_trust_provider" "idc" {
  description              = "${var.prefix} IAM Identity Center trust provider"
  policy_reference_name    = var.policy_reference_name
  trust_provider_type      = "user"
  user_trust_provider_type = "iam-identity-center"

  tags = {
    Name = "${var.prefix}-idc-trust-provider"
  }
}

# Step 2: Verified Access instance
resource "aws_verifiedaccess_instance" "main" {
  description = "${var.prefix} Verified Access instance"

  tags = {
    Name = "${var.prefix}-instance"
  }
}

resource "aws_verifiedaccess_instance_trust_provider_attachment" "idc" {
  verifiedaccess_instance_id       = aws_verifiedaccess_instance.main.id
  verifiedaccess_trust_provider_id = aws_verifiedaccess_trust_provider.idc.id
}

# Step 3: Verified Access group (default-deny when policy_document is omitted)
resource "aws_verifiedaccess_group" "app_group" {
  verifiedaccess_instance_id = aws_verifiedaccess_instance.main.id
  description                = "${var.prefix} application group"
  policy_document            = var.enable_allow_policy ? local.cedar_allow_policy : null

  depends_on = [aws_verifiedaccess_instance_trust_provider_attachment.idc]

  tags = {
    Name = "${var.prefix}-group"
  }
}

# Step 4: Verified Access endpoint in front of internal ALB
resource "aws_verifiedaccess_endpoint" "alb_app" {
  description            = "${var.prefix} internal ALB endpoint"
  verified_access_group_id = aws_verifiedaccess_group.app_group.id
  attachment_type        = "vpc"
  endpoint_type          = "load-balancer"
  application_domain     = var.application_domain
  domain_certificate_arn = var.domain_certificate_arn
  endpoint_domain_prefix = var.endpoint_domain_prefix
  security_group_ids     = var.security_group_ids

  load_balancer_options {
    load_balancer_arn = var.internal_alb_arn
    port              = var.alb_port
    protocol          = var.alb_protocol
    subnet_ids        = var.subnet_ids
  }

  tags = {
    Name = "${var.prefix}-alb-endpoint"
  }
}
