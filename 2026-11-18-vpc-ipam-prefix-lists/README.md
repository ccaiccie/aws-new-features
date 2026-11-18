# VPC IP Address Manager: pools, allocation rules and prefix list automation

Terraform practice lab for the AWS New Features video "VPC IP Address Manager (IPAM): Pools, Allocation Rules and Prefix List Automation" (YouTube playlist **aws new features**, Network Technician channel).

## What it builds

| Piece | Why it matters |
| --- | --- |
| `aws_vpc_ipam` (Advanced tier) with one operating Region | Creates the default private and public scopes; Advanced is needed for private IPv4 pools |
| Top-level pool `10.0.0.0/8`, no locale | Holds the whole internal block and only feeds child pools |
| Regional pool (locale = your Region) with a `/12` from the top-level pool | Only pools with a locale can allocate to VPCs; the pool-to-pool hand-off is an allocation too |
| Allocation rules: min `/16`, max `/24`, default `/20`, required tag `env=prod`, `auto_import = true` | Refuse oversize requests, require tags, adopt existing VPCs inside the pool |
| `aws_vpc_ipam_preview_next_cidr` | Shows the next free block before anything is built |
| `aws_vpc` with `ipv4_ipam_pool_id` + `ipv4_netmask_length = 20` | The VPC asks for a size, IPAM picks a non-overlapping block and records it |
| Managed prefix list + security group rule that references it | One rule covers every network in the list |

## Prerequisites

An AWS account (ideally a sandbox), credentials for Terraform, Terraform 1.6+, provider `hashicorp/aws` 6.73.0. If your account already has an IPAM (for example a delegated organization IPAM), run the lab in a separate sandbox account so the pools do not collide with your real address plan.

## Cost warning

The Advanced tier is billed per **active** IP address (an address on an attached network interface) per hour. The lab VPC has no instances, so the managed active IP count stays near zero, but **run `terraform destroy` when you finish**. Set `ipam_tier = "free"` to see what the Free tier refuses (private IPv4 pools need Advanced).

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
terraform apply
terraform output
```

Then, in the IPAM console (or CLI):

```bash
IPAM_POOL=$(terraform output -raw regional_pool_id)
aws ec2 get-ipam-pool-allocations --ipam-pool-id "$IPAM_POOL"          # the VPC allocation
aws ec2 get-ipam-resource-cidrs --ipam-scope-id <private-scope-id> \
  --query "IpamResourceCidrs[].[ResourceId,ResourceCidr,ComplianceStatus,OverlapStatus]" --output table
```

## Prefix list resolver (CLI, Advanced tier)

The provider version used here has no resource for the IPAM prefix list resolver (announced October 31, 2025), so try it with the AWS CLI after `apply`:

```bash
aws ec2 create-ipam-prefix-list-resolver help            # rules: static CIDR, IPAM pool CIDR, scope resource CIDR
aws ec2 create-ipam-prefix-list-resolver-target help     # links the resolver to the prefix list; --track-latest-version
aws ec2 describe-ipam-prefix-list-resolver-targets        # state, lastSyncedVersion, desiredVersion
```

Create a resolver with one rule "VPC resource CIDRs where tag env = prod", target it at `terraform output prefix_list_id`, then create a second tagged VPC and watch a new version appear. Remove the target before `terraform destroy` (or Terraform will see the prefix list entries change).

## Experiments

1. Set `vpc_netmask = 26` and run `plan`/`apply`: the pool's max netmask rule (`/24`) refuses it.
2. Remove the `env` tag from `aws_vpc.app` and apply: the allocation is refused by the tag rule.
3. Create a VPC by hand with `10.0.200.0/24` (inside the Regional pool) and watch auto import adopt it, or see it reported as unmanaged/overlapping.
4. Lower `prefix_list_max_entries` to 1 and add a second entry: the list is full; IPAM resolvers fail the same way.

## References

- What is IPAM? — https://docs.aws.amazon.com/vpc/latest/ipam/what-it-is-ipam.html
- How IPAM works — https://docs.aws.amazon.com/vpc/latest/ipam/how-it-works-ipam.html
- Automate prefix list updates with IPAM — https://docs.aws.amazon.com/vpc/latest/ipam/automate-prefix-list-updates.html
- IPAM tiers and pricing — https://aws.amazon.com/vpc/pricing/
