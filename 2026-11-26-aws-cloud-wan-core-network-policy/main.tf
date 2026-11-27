data "aws_availability_zones" "available" {
  state = "available"
}

# 1. Global Network container
resource "aws_networkmanager_global_network" "main" {
  description = "${var.project_name} Global Network"

  tags = {
    Name = "${var.project_name}-global-network"
  }
}

# 2. Core Network (creates a base policy first so attachments can bootstrap cleanly)
resource "aws_networkmanager_core_network" "main" {
  global_network_id  = aws_networkmanager_global_network.main.id
  description        = "${var.project_name} Core Network"
  create_base_policy = true

  tags = {
    Name = "${var.project_name}-core-network"
  }
}

# 3. Core Network Policy Document (isolated by default; toggles sharing via variable)
data "aws_networkmanager_core_network_policy_document" "main" {
  version = "2021.12"

  core_network_configuration {
    vpn_ecmp_support = true
    dns_support      = true
    asn_ranges       = [var.asn_range]

    edge_locations {
      location = var.aws_region
    }
  }

  segments {
    name                          = "prod"
    description                   = "Production workloads segment"
    require_attachment_acceptance = false
    isolate_attachments           = false
  }

  segments {
    name                          = "shared"
    description                   = "Shared services segment"
    require_attachment_acceptance = false
    isolate_attachments           = false
  }

  dynamic "segment_actions" {
    for_each = var.allow_prod_shared_sharing ? [1] : []
    content {
      action     = "share"
      mode       = "attachment-route"
      segment    = "shared"
      share_with = ["prod"]
    }
  }

  attachment_policies {
    rule_number     = 100
    description     = "Map attachments to segments using the Segment attachment tag"
    condition_logic = "or"

    conditions {
      type = "tag-exists"
      key  = "Segment"
    }

    action {
      association_method = "tag"
      tag_value_of_key   = "Segment"
    }
  }
}

# 4. Apply the policy document and set it LIVE
resource "aws_networkmanager_core_network_policy_attachment" "main" {
  core_network_id = aws_networkmanager_core_network.main.id
  policy_document = data.aws_networkmanager_core_network_policy_document.main.json
}

# 5. Production VPC + Subnet + Route Table
resource "aws_vpc" "prod" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-prod-vpc"
  }
}

resource "aws_subnet" "prod_attach" {
  vpc_id            = aws_vpc.prod.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-prod-attach-subnet"
  }
}

resource "aws_route_table" "prod" {
  vpc_id = aws_vpc.prod.id

  route {
    cidr_block       = "10.20.0.0/16"
    core_network_arn = aws_networkmanager_core_network.main.arn
  }

  tags = {
    Name = "${var.project_name}-prod-rt"
  }

  depends_on = [aws_networkmanager_vpc_attachment.prod]
}

resource "aws_route_table_association" "prod" {
  subnet_id      = aws_subnet.prod_attach.id
  route_table_id = aws_route_table.prod.id
}

# 6. Shared Services VPC + Subnet + Route Table
resource "aws_vpc" "shared" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-shared-vpc"
  }
}

resource "aws_subnet" "shared_attach" {
  vpc_id            = aws_vpc.shared.id
  cidr_block        = "10.20.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-shared-attach-subnet"
  }
}

resource "aws_route_table" "shared" {
  vpc_id = aws_vpc.shared.id

  route {
    cidr_block       = "10.10.0.0/16"
    core_network_arn = aws_networkmanager_core_network.main.arn
  }

  tags = {
    Name = "${var.project_name}-shared-rt"
  }

  depends_on = [aws_networkmanager_vpc_attachment.shared]
}

resource "aws_route_table_association" "shared" {
  subnet_id      = aws_subnet.shared_attach.id
  route_table_id = aws_route_table.shared.id
}

# 7. Cloud WAN VPC Attachments (tagged with Segment so attachment-policies places them)
resource "aws_networkmanager_vpc_attachment" "prod" {
  core_network_id = aws_networkmanager_core_network.main.id
  vpc_arn         = aws_vpc.prod.arn
  subnet_arns     = [aws_subnet.prod_attach.arn]

  tags = {
    Name    = "${var.project_name}-prod-attachment"
    Segment = "prod"
  }

  depends_on = [aws_networkmanager_core_network_policy_attachment.main]
}

resource "aws_networkmanager_vpc_attachment" "shared" {
  core_network_id = aws_networkmanager_core_network.main.id
  vpc_arn         = aws_vpc.shared.arn
  subnet_arns     = [aws_subnet.shared_attach.arn]

  tags = {
    Name    = "${var.project_name}-shared-attachment"
    Segment = "shared"
  }

  depends_on = [aws_networkmanager_core_network_policy_attachment.main]
}

# 8. Optional AWS RAM share (only required when sharing a core network with another AWS account)
# AWS docs require sharing the global core network resource from us-east-1.
resource "aws_ram_resource_share" "core_network" {
  count                     = var.enable_ram_share ? 1 : 0
  name                      = "${var.project_name}-core-network-share"
  allow_external_principals = true
}

resource "aws_ram_resource_association" "core_network" {
  count              = var.enable_ram_share ? 1 : 0
  resource_arn       = aws_networkmanager_core_network.main.arn
  resource_share_arn = aws_ram_resource_share.core_network[0].arn
}

resource "aws_ram_principal_association" "core_network" {
  count              = var.enable_ram_share && var.ram_share_account_id != "" ? 1 : 0
  principal          = var.ram_share_account_id
  resource_share_arn = aws_ram_resource_share.core_network[0].arn
}
