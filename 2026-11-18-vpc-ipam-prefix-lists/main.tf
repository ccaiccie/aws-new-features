# VPC IP Address Manager (IPAM): top-level and Regional pools, a VPC that takes
# its CIDR from the pool by size, and a managed prefix list used by a security group.

locals {
  tags = {
    lab = var.name_prefix
  }
}

resource "aws_vpc_ipam" "this" {
  description = "${var.name_prefix} IPAM"
  tier        = var.ipam_tier

  # The IPAM discovers resources in every operating Region. Include the home Region.
  operating_regions {
    region_name = var.region
  }

  # Lets terraform destroy remove scopes and pools in one go.
  cascade = true

  tags = local.tags
}

# Top-level pool in the default private scope. No locale: it only feeds child pools.
resource "aws_vpc_ipam_pool" "top" {
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  description    = "Top-level pool, whole internal block"
  cascade        = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-top" })
}

resource "aws_vpc_ipam_pool_cidr" "top" {
  ipam_pool_id = aws_vpc_ipam_pool.top.id
  cidr         = var.top_level_cidr
}

# Regional pool with a locale: only pools with a locale can allocate to VPCs.
resource "aws_vpc_ipam_pool" "regional" {
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.top.id
  locale              = var.region
  description         = "Regional pool for ${var.region}"
  cascade             = true

  # Allocation rules checked on every request.
  allocation_min_netmask_length     = 16
  allocation_max_netmask_length     = 24
  allocation_default_netmask_length = 20
  allocation_resource_tags = {
    env = var.environment_tag
  }

  # Adopt existing VPCs whose CIDRs already fall inside this pool.
  auto_import = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-${var.region}" })
}

# Pool-to-pool allocation: the top-level pool gives a /12 to the Regional pool.
resource "aws_vpc_ipam_pool_cidr" "regional" {
  ipam_pool_id   = aws_vpc_ipam_pool.regional.id
  netmask_length = var.regional_netmask

  depends_on = [aws_vpc_ipam_pool_cidr.top]
}

# What would the pool hand out next? Useful in a change request.
resource "aws_vpc_ipam_preview_next_cidr" "next" {
  ipam_pool_id   = aws_vpc_ipam_pool.regional.id
  netmask_length = var.vpc_netmask

  depends_on = [aws_vpc_ipam_pool_cidr.regional]
}

# The VPC asks for a size, not a range. IPAM picks the next free block and records the allocation.
resource "aws_vpc" "app" {
  ipv4_ipam_pool_id    = aws_vpc_ipam_pool.regional.id
  ipv4_netmask_length  = var.vpc_netmask
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Required by the pool's allocation_resource_tags rule.
  tags = merge(local.tags, { Name = "${var.name_prefix}-app", env = var.environment_tag })

  depends_on = [aws_vpc_ipam_pool_cidr.regional]
}

# Customer-managed prefix list fed from the Regional pool CIDR.
# In production, attach an IPAM prefix list resolver instead (see README), so the
# list follows your VPCs automatically.
resource "aws_ec2_managed_prefix_list" "internal" {
  name           = "${var.name_prefix}-internal"
  address_family = "IPv4"
  max_entries    = var.prefix_list_max_entries

  entry {
    cidr        = aws_vpc_ipam_pool_cidr.regional.cidr
    description = "Regional IPAM pool ${var.region}"
  }

  tags = local.tags
}

# One security group rule covers every network in the prefix list.
resource "aws_security_group" "internal_https" {
  name        = "${var.name_prefix}-internal-https"
  description = "HTTPS from internal networks in the prefix list"
  vpc_id      = aws_vpc.app.id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "https_from_internal" {
  security_group_id = aws_security_group.internal_https.id
  prefix_list_id    = aws_ec2_managed_prefix_list.internal.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from the internal prefix list"
}
