# ------------------------------------------------------------------------------
# Part 1: VPC, Subnet, Security Group & CloudWatch Connection Logs
# ------------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "${var.name_prefix}-private-subnet" }
}

resource "aws_security_group" "cvpn" {
  name        = "${var.name_prefix}-cvpn-sg"
  description = "Security group attached to Client VPN network interfaces"
  vpc_id      = aws_vpc.lab.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_cloudwatch_log_group" "cvpn" {
  name              = "/aws/client-vpn/${var.name_prefix}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "cvpn" {
  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.cvpn.name
}

# ------------------------------------------------------------------------------
# Part 2: Client Connect Handler Lambda (MUST start with "AWSClientVPN-")
# ------------------------------------------------------------------------------

data "archive_file" "handler_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/connect_handler.py"
  output_path = "${path.module}/build/connect_handler.zip"
}

resource "aws_iam_role" "handler_role" {
  name = "${var.name_prefix}-cvpn-handler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "handler_logs" {
  role       = aws_iam_role.handler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "connect_handler" {
  # Required official prefix: AWSClientVPN-
  function_name    = "AWSClientVPN-${var.name_prefix}-handler"
  role             = aws_iam_role.handler_role.arn
  handler          = "connect_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.handler_zip.output_path
  source_code_hash = data.archive_file.handler_zip.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      ALLOWED_PLATFORMS = var.allowed_platforms
    }
  }
}

# ------------------------------------------------------------------------------
# Part 3: AWS Client VPN Endpoint, Association & Authorization Rule
# ------------------------------------------------------------------------------

resource "aws_ec2_client_vpn_endpoint" "lab" {
  description            = "Client VPN lab with connect handler and connection logging"
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = var.client_cidr_block
  vpc_id                 = aws_vpc.lab.id
  security_group_ids     = [aws_security_group.cvpn.id]
  split_tunnel           = true
  transport_protocol     = "udp"
  vpn_port               = 443

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_root_certificate_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.cvpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.cvpn.name
  }

  client_connect_options {
    enabled             = true
    lambda_function_arn = aws_lambda_function.connect_handler.arn
  }

  tags = { Name = "${var.name_prefix}-endpoint" }
}

resource "aws_ec2_client_vpn_network_association" "private" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.lab.id
  subnet_id              = aws_subnet.private.id
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc_access" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.lab.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
}
