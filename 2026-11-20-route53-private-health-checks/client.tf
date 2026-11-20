# Optional test client reachable with SSM Session Manager through interface
# endpoints (the VPC has no internet). Use it to resolve the failover record.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "client" {
  count              = var.enable_test_client ? 1 : 0
  name               = "${var.name}-client"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "client_ssm" {
  count      = var.enable_test_client ? 1 : 0
  role       = aws_iam_role.client[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "client" {
  count = var.enable_test_client ? 1 : 0
  name  = "${var.name}-client"
  role  = aws_iam_role.client[0].name
}

resource "aws_security_group" "client" {
  count       = var.enable_test_client ? 1 : 0
  name        = "${var.name}-client"
  description = "Test client"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name}-client" }
}

resource "aws_vpc_security_group_egress_rule" "client_all_vpc" {
  count             = var.enable_test_client ? 1 : 0
  security_group_id = aws_security_group.client[0].id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "Web servers, DNS and SSM endpoints inside the VPC"
}

resource "aws_security_group" "endpoints" {
  count       = var.enable_test_client ? 1 : 0
  name        = "${var.name}-ssm-endpoints"
  description = "SSM interface endpoints"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name}-ssm-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count                        = var.enable_test_client ? 1 : 0
  security_group_id            = aws_security_group.endpoints[0].id
  referenced_security_group_id = aws_security_group.client[0].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from the test client"
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = var.enable_test_client ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])
  vpc_id              = aws_vpc.lab.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[2].id] # one AZ is enough for a lab
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
  tags                = { Name = "${var.name}-${each.key}" }
}

resource "aws_instance" "client" {
  count                  = var.enable_test_client ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[2].id
  vpc_security_group_ids = [aws_security_group.client[0].id]
  iam_instance_profile   = aws_iam_instance_profile.client[0].name

  metadata_options {
    http_tokens = "required"
  }

  tags       = { Name = "${var.name}-client" }
  depends_on = [aws_vpc_endpoint.ssm]
}
