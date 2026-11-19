# Transit Gateway network function attachments for Gateway Load Balancer

Terraform practice lab for the AWS New Features video on the native AWS Transit Gateway and Gateway Load Balancer integration (YouTube playlist **aws new features**, Network Technician channel).

Posted November 17, 2026: AWS Transit Gateway now supports **network function attachments of type Gateway Load Balancer**. You connect the transit gateway to a Gateway Load Balancer **VPC endpoint service** that fronts your firewalls. Transit Gateway creates and manages the Gateway Load Balancer endpoints in the Availability Zones you choose, so you no longer build dedicated endpoint subnets and route tables. The endpoint service can be in another AWS account. The attachment also supports **context sharing**: Transit Gateway adds resource context (attachment, VPC, subnet, security groups) to traffic sent to your firewall.

## Honest limit: no Terraform resource for the attachment yet

`hashicorp/aws` **6.73.0** (pinned here; the latest release when this lab was written on November 19, 2026) has **no resource for a transit gateway network function attachment**, and none is listed in the unreleased 6.74.0 changelog. The Network Manager **context store** is not in the provider either.

So the lab is two-phase:

1. **Terraform** builds everything that is supported: spoke VPCs, the security VPC with the Gateway Load Balancer, a GENEVE target group, optional appliances, the VPC endpoint service, the transit gateway (with encryption support disabled), spoke attachments and two transit gateway route tables.
2. **AWS CLI** ([`scripts/nf-attachment.sh`](./scripts/nf-attachment.sh)) creates the network function attachment. You paste its `tgw-attach-...` ID into `nf_attachment_id` and apply again; Terraform then uses the standard `aws_ec2_transit_gateway_route_table_association` and `aws_ec2_transit_gateway_route` resources, which take any attachment ID.

Nothing in the `.tf` files pretends to create the attachment. When the provider adds a resource, move it into Terraform and retire the script.

## What it builds

| Piece | Why it matters |
| --- | --- |
| Spoke VPCs A (`10.1.0.0/16`) and B (`10.2.0.0/16`), a /24 per AZ, route `10.0.0.0/8` → transit gateway | Traffic to inspect |
| Security VPC (`10.100.0.0/16`) with one appliance subnet per AZ | Holds the GWLB and appliances. **No transit gateway attachment, no endpoint subnets, no endpoint route tables**: that is the point of the feature |
| `aws_lb` (gateway), `aws_lb_target_group` (GENEVE 6081), `aws_lb_listener` | Gateway Load Balancer in front of the appliances |
| Optional `aws_instance` appliances (`appliance_ami_id`) + target attachments | Prerequisite: the GWLB must have **healthy appliance targets** before you create the attachment |
| `aws_vpc_endpoint_service` with `gateway_load_balancer_arns` | The endpoint service the attachment connects to |
| `aws_ec2_transit_gateway` with `encryption_support = "disable"` and default association/propagation off | Creation is rejected if encryption support is `enabled`, `enabling` or `disabling` |
| Route table **spokes** (associated with both spoke attachments) | Pre-inspection. Phase 2 adds a **static** route `10.0.0.0/8` → network function attachment |
| Route table **inspection** (spoke attachments propagate into it) | Post-inspection. Phase 2 associates the network function attachment here, so inspected traffic is forwarded to the destination spoke |
| Optional (`enable_network_manager = true`) global network + transit gateway registration | Prerequisites for context sharing and the Network Manager topology view |

## Prerequisites

- An AWS sandbox account; Terraform 1.6+; provider `hashicorp/aws` 6.73.0 (lock file included).
- A current AWS CLI v2 that has `create-transit-gateway-network-function-attachment` (update the CLI if the command is missing).
- A Region where the feature is offered: all commercial Regions with both Transit Gateway and Gateway Load Balancer **except Middle East (Bahrain) and Middle East (UAE)**, plus AWS GovCloud (US-East) and (US-West).
- **Not** the Availability Zone with ID `use1-az3`, which the attachment does not support. Check with `aws ec2 describe-availability-zones --query 'AvailabilityZones[].[ZoneName,ZoneId]'`.
- A GENEVE-capable appliance AMI (firewall vendor or your own) that answers health checks on `health_check_port`. Without healthy targets the prerequisite is not met.
- The principal creating the attachment needs `ec2:DescribeVpcEndpointServices`.
- Only the **transit gateway owner** can create, modify or delete the attachment.

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars   # set appliance_ami_id, region, azs
terraform init
terraform apply                                 # phase 1
export AWS_REGION=us-east-1                     # same as var.region

scripts/nf-attachment.sh create                 # creates the attachment; note the tgw-attach-... ID
scripts/nf-attachment.sh accept tgw-attach-...  # only if acceptance_required = true (state: pendingAcceptance)
scripts/nf-attachment.sh status tgw-attach-...  # wait for "available"

# phase 2: set nf_attachment_id = "tgw-attach-..." in terraform.tfvars
terraform apply
```

Equivalent raw commands (from the AWS Transit Gateway Guide):

```bash
aws ec2 create-transit-gateway-network-function-attachment \
  --transit-gateway-id <tgw-id> \
  --service-name <gwlb-endpoint-service-name> \
  --availability-zone-ids <az-id-1> <az-id-2>        # or --availability-zones <az-name> ...; up to 16 AZs

aws ec2 accept-vpc-endpoint-connections \
  --service-id <vpce-svc-id> --transit-gateway-attachment-ids <tgw-attach-id>
```

## Things to try

- **Look at it**: VPC console → Transit gateway attachments: the attachment has type **Network function**. With `enable_network_manager = true`, Network Manager → your global network → Transit gateways → Topology tree shows a network function icon.
- **Static only**: try to enable propagation from the network function attachment. It is not supported; only route table associations and static routes are.
- **Add or remove an AZ**: `scripts/nf-attachment.sh remove-az <attach-id> <az-id>`. The attachment goes `modifying` → `available`; an unsupported AZ sends it to `rollingBack` and it restores the previous configuration. You must keep at least one AZ. With acceptance required, every AZ you add creates a new endpoint connection to accept.
- **Cross-account** (optional, two accounts): the endpoint service owner allows the transit gateway owner's account with the special permission type. Only an account root ARN is accepted:

  ```bash
  aws ec2 modify-vpc-endpoint-service-permissions \
    --service-id <vpce-svc-id> \
    --permission-type transit-gateway-attachment \
    --add-allowed-principals arn:aws:iam::<tgw-owner-account-id>:root
  ```

  Terraform's `allowed_principals` / `aws_vpc_endpoint_service_allowed_principal` set the normal permission, not this permission type, so use the CLI.

## Context sharing (CLI / console only)

Context sharing lets the firewall use VPCs, subnets, security groups and transit gateway attachments alongside IP addresses in its policies. Transit Gateway adds **source** context identifiers to traffic routed through a network function attachment; the firewall resolves them from a **context store** in Network Manager.

1. `enable_network_manager = true` and apply (global network + transit gateway registration).
2. `aws networkmanager create-context-store --global-network-id <global-network-id>` (state `PENDING` → `AVAILABLE`).
3. `aws networkmanager associate-context-store --context-store-id <context-store-id> --transit-gateway-arn <tgw-arn>` (`ASSOCIATING` → `ASSOCIATED`).
4. Grant your firewall integration read access: an IAM role it can assume (principal ARN and external ID from your firewall provider) with `networkmanager:ListContexts`, `networkmanager:GetContextVersion` and `networkmanager:ListContextChanges` on the context store ARN. AWS Network Firewall uses its own service role instead.

Limits from the docs: one context store per global network; one context store per transit gateway; only traffic through a network function attachment (Network Firewall or GWLB type); up to five security groups per resource (more than five = no security group context); not shared across inter-Region peering. Individual context records are visible only through the Network Manager API or CLI.

## Clean up

Order matters: routes that still point at a deleted attachment become **blackhole** routes and drop traffic.

```bash
# 1. remove the route and association: set nf_attachment_id = "" in terraform.tfvars
terraform apply
# 2. delete the attachment (Transit Gateway removes the GWLB endpoints it created)
scripts/nf-attachment.sh delete tgw-attach-...
# 3. (if you created one) disassociate and delete the context store with the networkmanager CLI
# 4. destroy the rest
terraform destroy
```

## Cost warning

Transit gateway attachment-hours and data processing, Gateway Load Balancer and endpoint hours and data, the appliance instances (and their licences) all bill while the lab is up. The sources for this lab do not list a separate price for the network function attachment, so check the Transit Gateway and Elastic Load Balancing pricing pages. **Destroy the lab when you finish.**

## Sources

- What's New, November 17, 2026: https://aws.amazon.com/about-aws/whats-new/2026/11/transit-gateway-gwlb-integration/
- Network function attachments: https://docs.aws.amazon.com/vpc/latest/tgw/tgw-nf-fw.html
- Manage a network function attachment of type Gateway Load Balancer: https://docs.aws.amazon.com/vpc/latest/tgw/manage-nf-attachment-gwlb.html
- Accept or reject: https://docs.aws.amazon.com/vpc/latest/tgw/accept-reject-firewall-attachment.html
- Route traffic: https://docs.aws.amazon.com/vpc/latest/tgw/route-traffic-nf-attachment.html
- View attachments: https://docs.aws.amazon.com/vpc/latest/tgw/view-nf-attachment-nm.html
- Context sharing: https://docs.aws.amazon.com/network-manager/latest/tgwnm/context-stores.html
- Appliance scenario (appliance mode): https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-appliance-scenario.html
- What is a Gateway Load Balancer: https://docs.aws.amazon.com/elasticloadbalancing/latest/gateway/introduction.html
