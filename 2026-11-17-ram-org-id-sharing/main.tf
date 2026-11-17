# ---------------------------------------------------------------------------
# The organization this account belongs to. Its ID (o-...) is part of the
# organization and OU ARNs that RAM uses as principals.
# ---------------------------------------------------------------------------
data "aws_organizations_organization" "this" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  org_principal = var.org_share_principal != "" ? var.org_share_principal : data.aws_organizations_organization.this.arn
  azs           = slice(data.aws_availability_zones.available.zone_ids, 0, 2)
}

# Optional: turn on sharing with AWS Organizations from the RAM side (management
# account only). Enabling trusted access only from the Organizations side does
# not create the RAM service-linked role.
resource "aws_ram_sharing_with_organization" "this" {
  count = var.enable_org_sharing ? 1 : 0
}

# ---------------------------------------------------------------------------
# Network-account resources to share.
# ---------------------------------------------------------------------------
resource "aws_vpc" "shared" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# Subnets are placed by AZ ID so every account sees the same physical location.
resource "aws_subnet" "shared" {
  count                = 2
  vpc_id               = aws_vpc.shared.id
  cidr_block           = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone_id = local.azs[count.index]

  tags = { Name = "${var.name_prefix}-shared-${local.azs[count.index]}" }
}

resource "aws_ec2_managed_prefix_list" "onprem" {
  name           = "${var.name_prefix}-onprem"
  address_family = "IPv4"
  max_entries    = 10

  dynamic "entry" {
    for_each = var.onprem_prefixes
    content {
      cidr        = entry.value
      description = "on-premises example"
    }
  }
}

resource "aws_ec2_transit_gateway" "hub" {
  count       = var.create_transit_gateway ? 1 : 0
  description = "${var.name_prefix} hub"

  # Leave attachment requests from consumer accounts for the owner to accept.
  auto_accept_shared_attachments = "disable"

  tags = { Name = "${var.name_prefix}-tgw" }
}

# ---------------------------------------------------------------------------
# Share 1: organization-scoped. Subnets can be shared only inside the
# organization, so this share does not allow external principals.
# Accounts that join the org (or OU) get access automatically; accounts that
# leave lose it.
# ---------------------------------------------------------------------------
resource "aws_ram_resource_share" "org" {
  name                      = "${var.name_prefix}-org-scope"
  allow_external_principals = false

  tags = { Purpose = "org-or-ou-principal" }
}

resource "aws_ram_resource_association" "org_subnets" {
  count              = 2
  resource_arn       = aws_subnet.shared[count.index].arn
  resource_share_arn = aws_ram_resource_share.org.arn
}

resource "aws_ram_resource_association" "org_prefix_list" {
  resource_arn       = aws_ec2_managed_prefix_list.onprem.arn
  resource_share_arn = aws_ram_resource_share.org.arn
}

resource "aws_ram_principal_association" "org" {
  principal          = local.org_principal
  resource_share_arn = aws_ram_resource_share.org.arn

  depends_on = [aws_ram_sharing_with_organization.this]
}

# ---------------------------------------------------------------------------
# Share 2: migration share. Individual account principals, external principals
# allowed, and retain sharing on account leave organization = true. RAM sends
# an invitation even inside the org; once accepted, access survives the
# account leaving the organization. Org-only types (subnets, security groups)
# cannot be in this share.
# ---------------------------------------------------------------------------
resource "aws_ram_resource_share" "retain" {
  count                     = length(var.retain_share_account_ids) > 0 ? 1 : 0
  name                      = "${var.name_prefix}-retain-on-leave"
  allow_external_principals = true

  resource_share_configuration {
    retain_sharing_on_account_leave_organization = true
  }

  tags = { Purpose = "account-migration" }
}

resource "aws_ram_resource_association" "retain_tgw" {
  count              = length(var.retain_share_account_ids) > 0 && var.create_transit_gateway ? 1 : 0
  resource_arn       = aws_ec2_transit_gateway.hub[0].arn
  resource_share_arn = aws_ram_resource_share.retain[0].arn
}

resource "aws_ram_resource_association" "retain_prefix_list" {
  count              = length(var.retain_share_account_ids) > 0 ? 1 : 0
  resource_arn       = aws_ec2_managed_prefix_list.onprem.arn
  resource_share_arn = aws_ram_resource_share.retain[0].arn
}

resource "aws_ram_principal_association" "retain" {
  for_each           = toset(var.retain_share_account_ids)
  principal          = each.value
  resource_share_arn = aws_ram_resource_share.retain[0].arn
}
