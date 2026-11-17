# AWS RAM with Organizations: org, OU and account sharing, and what changes with the Org ID

Terraform practice lab for the AWS New Features video "AWS RAM with Organizations: Sharing and Org ID Changes" (YouTube playlist **aws new features**, Network Technician channel).

## What it builds

| Piece | Why it matters |
| --- | --- |
| `data.aws_organizations_organization` | Shows the organization ID (`o-...`) that is embedded in organization and OU principal ARNs |
| Optional `aws_ram_sharing_with_organization` | Turns on sharing with AWS Organizations from the RAM side (management account only); this creates the `AWSServiceRoleForResourceAccessManager` service-linked role |
| VPC with two subnets (placed by AZ ID) | Subnets for VPC sharing; subnets can be shared only inside the organization |
| Customer-managed prefix list | Shareable with the org, an OU or individual accounts; existing references keep working after an unshare |
| Transit gateway (optional) | Shareable with individual accounts in or outside the organization; `auto_accept_shared_attachments` is left disabled |
| Share 1 `org-scope` | `allow_external_principals = false`; subnets + prefix list shared to the organization ARN (default) or an OU ARN you choose |
| Share 2 `retain-on-leave` | `allow_external_principals = true` and `resource_share_configuration { retain_sharing_on_account_leave_organization = true }`; transit gateway + prefix list shared to the account IDs you list |

## Prerequisites

- An account in AWS Organizations with sharing with AWS Organizations turned on (set `enable_org_sharing = true` if you run the lab in the management account and it is not on yet).
- To see invitations and the retain behaviour, a second account ID for `retain_share_account_ids`.
- Terraform 1.6+, provider `hashicorp/aws` 6.73.0 (the `resource_share_configuration` block needs 6.35.0 or later).

## Cost warning

RAM sharing, VPCs, subnets and prefix lists have no charge. A transit gateway is billed for its attachments and the data it processes (the lab creates no attachments; check current Transit Gateway pricing). Set `create_transit_gateway = false` to skip it. **Run `terraform destroy` when you finish.**

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars   # edit the account IDs and principal
terraform init
terraform validate
terraform plan
terraform apply
terraform output organization_id
terraform output check_commands
```

In the owner (network) account:

```bash
aws ram get-resource-shares --resource-owner SELF
aws ram list-principals --resource-owner SELF
aws ram list-resources --resource-owner SELF
```

In a consumer account listed in `retain_share_account_ids`:

```bash
aws ram get-resource-share-invitations          # retain share: an invitation, even inside the org
aws ram accept-resource-share-invitation --resource-share-invitation-arn <arn>
aws ram get-resource-shares --resource-owner OTHER-ACCOUNTS
aws ec2 describe-transit-gateways               # visible once the invitation is accepted
```

Invitations for transit gateways, prefix lists, subnets and Route 53 forwarding rules can be accepted for 7 days; most other types (for example IPAM pools) for 12 hours.

## Experiments

1. Set `org_share_principal` to an OU ARN. Move a test account out of that OU and watch it lose access to the subnets and prefix list.
2. Try to add a subnet to the retain share (add an `aws_ram_resource_association`). RAM rejects org-only resource types in a share with retain on leave.
3. Try to use an OU ARN in the retain share: the variable validation stops it, because retain sharing applies only to individual account principals.
4. Search your own policies for `aws:PrincipalOrgID` and `ram:Principal` conditions that name the current `o-` ID; these must change if the organization is recreated.
5. Unshare the prefix list from a consumer that references it in a security group, and confirm the existing reference keeps working.

## What happens when the Org ID changes (summary)

- Account leaves the organization: by default it loses access to resources shared to the org, its OU, or directly to it while it was a member. Shares created with retain on leave (account principals, invitation accepted) keep access.
- Organization deleted and recreated: all members must be removed first, the old organization cannot be recovered, and the new organization has a new ID. Turn sharing on again and recreate shares with the new organization or OU ARNs.
- Route 53 Resolver rules: if an account moves to an OU the rule is not shared with, its VPC associations are deleted. Share to the destination OU first.
- Shared subnets: participants must be in the same organization; plan to move or rebuild those workloads.

## References

- Sharing your AWS resources (enable sharing with Organizations, RetainSharingOnAccountLeaveOrganization) — https://docs.aws.amazon.com/ram/latest/userguide/getting-started-sharing.html
- RAM maintains shares when accounts change organizations (Feb 27, 2026) — https://aws.amazon.com/about-aws/whats-new/2026/02/aws-resource-access-manager/
- Shareable AWS resources — https://docs.aws.amazon.com/ram/latest/userguide/shareable.html
- Disabling sharing with AWS Organizations — https://docs.aws.amazon.com/ram/latest/userguide/security-disable-sharing-with-orgs.html
- Example SCPs for RAM — https://docs.aws.amazon.com/ram/latest/userguide/security-scp.html
- Working with shared subnets — https://docs.aws.amazon.com/vpc/latest/userguide/vpc-sharing-share-subnet-working-with.html
- Shared transit gateways — https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-share.html
- Sharing Resolver rules — https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-rules-managing.html
- Work with shared prefix lists — https://docs.aws.amazon.com/vpc/latest/userguide/work-with-shared-prefixes.html
- Share an IPAM pool using AWS RAM — https://docs.aws.amazon.com/vpc/latest/ipam/share-pool-ipam.html
- Removing a member account — https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_remove.html
- Deleting an organization — https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_org_delete.html
- Terraform `aws_ram_resource_share` — https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_share
