output "organization_id" {
  description = "The o- ID of this account's organization. It changes if the account moves or the org is recreated."
  value       = data.aws_organizations_organization.this.id
}

output "org_share_principal" {
  description = "Principal used by the org-scoped share (org ARN or OU ARN)."
  value       = local.org_principal
}

output "org_share_arn" {
  value = aws_ram_resource_share.org.arn
}

output "retain_share_arn" {
  value = try(aws_ram_resource_share.retain[0].arn, null)
}

output "transit_gateway_id" {
  value = try(aws_ec2_transit_gateway.hub[0].id, null)
}

output "prefix_list_id" {
  value = aws_ec2_managed_prefix_list.onprem.id
}

output "check_commands" {
  description = "AWS CLI commands to inspect the shares (run in the lab Region)."
  value = {
    shares_i_own       = "aws ram get-resource-shares --resource-owner SELF --region ${var.region}"
    principals         = "aws ram list-principals --resource-owner SELF --region ${var.region}"
    resources          = "aws ram list-resources --resource-owner SELF --region ${var.region}"
    consumer_invites   = "aws ram get-resource-share-invitations --region ${var.region}   # run in a consumer account"
    consumer_accept    = "aws ram accept-resource-share-invitation --resource-share-invitation-arn <arn> --region ${var.region}   # consumer account"
    consumer_shared_in = "aws ram get-resource-shares --resource-owner OTHER-ACCOUNTS --region ${var.region}   # consumer account"
  }
}
