data "aws_availability_zones" "available" {
  state = "available"
}

# 1. AWS VPC and private subnet (non-overlapping with Azure VNet 10.20.0.0/16)
resource "aws_vpc" "lab" {
  cidr_block           = var.aws_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.aws_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.name_prefix}-private-a"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# 2. Transit Gateway (local to var.aws_region) and VPC attachment
resource "aws_ec2_transit_gateway" "lab" {
  description                     = "Local-Region Transit Gateway for AWS Interconnect - multicloud with Azure"
  amazon_side_asn                 = var.tgw_amazon_side_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name = "${var.name_prefix}-tgw"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "lab" {
  transit_gateway_id = aws_ec2_transit_gateway.lab.id
  vpc_id             = aws_vpc.lab.id
  subnet_ids         = [aws_subnet.private.id]

  tags = {
    Name = "${var.name_prefix}-tgw-vpc-att"
  }
}

# Route Azure VNet CIDR from the AWS VPC subnet to the Transit Gateway
resource "aws_route" "to_azure_via_tgw" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.azure_vnet_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.lab.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.lab]
}

# 3. Direct Connect gateway (the required AWS attach point for AWS Interconnect)
resource "aws_dx_gateway" "lab" {
  name            = "${var.name_prefix}-dxgw"
  amazon_side_asn = tostring(var.dxgw_amazon_side_asn)
}

# 4. Transit Gateway to Direct Connect gateway association with allowed prefixes
resource "aws_dx_gateway_association" "tgw" {
  dx_gateway_id         = aws_dx_gateway.lab.id
  associated_gateway_id = aws_ec2_transit_gateway.lab.id

  allowed_prefixes = [
    var.aws_vpc_cidr,
  ]
}

# 5. CloudWatch utilization alarm (created once interconnect_connection_id is supplied)
resource "aws_cloudwatch_metric_alarm" "interconnect_egress_high" {
  count = var.interconnect_connection_id != "" ? 1 : 0

  alarm_name          = "${var.name_prefix}-egress-utilization-high"
  alarm_description   = "Alert when AWS Interconnect ConnectionUtilizationEgress exceeds threshold so you can scale bandwidth in place."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ConnectionUtilizationEgress"
  namespace           = "AWS/Interconnect"
  period              = 300
  statistic           = "Average"
  threshold           = var.utilization_alarm_threshold_percent
  treat_missing_data  = "notBreaching"

  dimensions = {
    (var.interconnect_metric_dimension_name) = var.interconnect_connection_id
  }
}
