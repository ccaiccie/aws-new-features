terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# 1. AWS Transit Gateway (ECMP enabled for active/active BGP VPN scaling)
# -----------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "main" {
  description                     = "${var.project_name} Transit Gateway"
  amazon_side_asn                 = var.tgw_asn
  vpn_ecmp_support                = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = {
    Name = "${var.project_name}-tgw"
  }
}

# -----------------------------------------------------------------------------
# 2. Spoke VPC A (10.10.0.0/16) with dedicated /28 TGW attachment subnet
# -----------------------------------------------------------------------------
resource "aws_vpc" "spoke_a" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc-a"
  }
}

resource "aws_subnet" "spoke_a_tgw" {
  vpc_id            = aws_vpc.spoke_a.id
  cidr_block        = "10.10.255.0/28"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-vpc-a-tgw-subnet"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_a" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.spoke_a.id
  subnet_ids         = [aws_subnet.spoke_a_tgw.id]

  tags = {
    Name = "${var.project_name}-attach-vpc-a"
  }
}

resource "aws_route_table" "spoke_a" {
  vpc_id = aws_vpc.spoke_a.id

  route {
    cidr_block         = var.onprem_cidr
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-vpc-a"
  }

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke_a]
}

resource "aws_route_table_association" "spoke_a_tgw" {
  subnet_id      = aws_subnet.spoke_a_tgw.id
  route_table_id = aws_route_table.spoke_a.id
}

# -----------------------------------------------------------------------------
# 3. Spoke VPC B (10.20.0.0/16) with dedicated /28 TGW attachment subnet
# -----------------------------------------------------------------------------
resource "aws_vpc" "spoke_b" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc-b"
  }
}

resource "aws_subnet" "spoke_b_tgw" {
  vpc_id            = aws_vpc.spoke_b.id
  cidr_block        = "10.20.255.0/28"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-vpc-b-tgw-subnet"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_b" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.spoke_b.id
  subnet_ids         = [aws_subnet.spoke_b_tgw.id]

  tags = {
    Name = "${var.project_name}-attach-vpc-b"
  }
}

resource "aws_route_table" "spoke_b" {
  vpc_id = aws_vpc.spoke_b.id

  route {
    cidr_block         = var.onprem_cidr
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-vpc-b"
  }

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke_b]
}

resource "aws_route_table_association" "spoke_b_tgw" {
  subnet_id      = aws_subnet.spoke_b_tgw.id
  route_table_id = aws_route_table.spoke_b.id
}

# -----------------------------------------------------------------------------
# 4. Simulated / Disposable Customer Gateway Resource
# -----------------------------------------------------------------------------
resource "aws_customer_gateway" "onprem" {
  bgp_asn    = var.cgw_asn
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"

  tags = {
    Name = "${var.project_name}-cgw"
  }
}

# -----------------------------------------------------------------------------
# 5. AWS Site-to-Site VPN Connection attached to Transit Gateway (2 Tunnels)
# -----------------------------------------------------------------------------
resource "aws_vpn_connection" "tgw_vpn" {
  customer_gateway_id = aws_customer_gateway.onprem.id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = "ipsec.1"

  static_routes_only  = var.static_routes_only
  enable_acceleration = var.enable_acceleration

  tunnel1_inside_cidr  = var.tunnel1_inside_cidr
  tunnel2_inside_cidr  = var.tunnel2_inside_cidr
  tunnel1_ike_versions = ["ikev2"]
  tunnel2_ike_versions = ["ikev2"]

  # For Accelerated VPN, the customer gateway device must initiate IKE (add).
  tunnel1_startup_action = "add"
  tunnel2_startup_action = "add"

  tags = {
    Name = "${var.project_name}-tgw-vpn"
  }
}

# -----------------------------------------------------------------------------
# 6. Static Route on TGW Route Table (only created when static_routes_only=true)
# -----------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route" "onprem_static" {
  count                          = var.static_routes_only ? 1 : 0
  destination_cidr_block         = var.onprem_cidr
  transit_gateway_attachment_id  = aws_vpn_connection.tgw_vpn.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.main.association_default_route_table_id
}
