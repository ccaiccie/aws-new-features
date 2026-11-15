# VPC Lattice private domain-name targets (IN_VPC DNS resolution)

Terraform practice lab for the AWS New Features video "VPC Lattice Private Domain-Name Targets: IN_VPC DNS and Resource Gateways" (YouTube playlist **aws new features**, Network Technician channel).

A consumer VPC reaches `payments.svc.internal`, a name that exists **only** in a Route 53 private hosted zone associated with a different (producer) VPC. There is no peering, no transit gateway and no route between the two VPCs. VPC Lattice carries the traffic, and the resource gateway resolves the private name because its DNS resolution is set to `IN_VPC`.

## What it builds

| Piece | Where | Why it matters |
| --- | --- | --- |
| Private hosted zone `svc.internal` + A record | Producer VPC | The private DNS source the resource gateway reads |
| Resource gateway, `resource_config_dns_resolution = "IN_VPC"` | Producer VPC, two AZs | Immutable; sends target lookups to the VPC's DHCP-option-set DNS (AmazonProvidedDNS) |
| Resource configuration, type `SINGLE`, `dns_resource`, TCP 8443, `custom_domain_name` | Producer account | Names the FQDN; the custom domain name is immutable |
| Service network (`auth_type = NONE`) + resource association with `private_dns_enabled = true` | Producer account | Owner-side switch for consumer hosted zones |
| Service network VPC association, `private_dns_preference = SPECIFIED_DOMAINS_ONLY` | Consumer VPC | Consumer-side switch, fixed at creation |
| Optional target web server (python http.server on 8443) and a test client | One per VPC | The client writes `LATTICE-TEST` lines to its console log |

## Prerequisites

- An AWS account, credentials (`aws configure` or environment variables), AWS CLI v2 and Terraform 1.6+
- A Region where VPC Lattice is available (default `us-east-1`)
- Permissions for VPC, EC2, Route 53 and VPC Lattice

## Cost warning

VPC Lattice bills the service network owner per hour for each resource associated with a service network and per GB of data processed. Two `t3.micro` instances run while the lab is up (set `create_instances = false` to skip them). The lab creates no NAT gateways. **Run `terraform destroy` when you finish.**

## Steps

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Wait three to five minutes, then read the client console log (it tests once a minute for 30 minutes):

```bash
aws ec2 get-console-output --latest --instance-id "$(terraform output -raw client_instance_id)" \
  --query Output --output text | grep LATTICE-TEST
```

You should see `payments.svc.internal` resolve to a VPC Lattice address (not the producer's 10.0.x.x address) and the response `hello from payments.svc.internal via VPC Lattice`.

Confirm the Lattice-owned zone in the consumer VPC:

```bash
aws route53 list-hosted-zones-by-vpc --vpc-id "$(terraform output -raw consumer_vpc_id)" --vpc-region us-east-1
```

Look for `Owner.OwningService = vpc-lattice.amazonaws.com`. That zone does not appear in your normal hosted zone list and you cannot edit it.

## Experiments

1. **Silent DNS failure.** Set `private_dns_preference = "VERIFIED_DOMAINS_ONLY"` (the API default) and apply. The VPC association is replaced, no hosted zone is created, and the client logs `no-dns` with no error anywhere. Put it back to `SPECIFIED_DOMAINS_ONLY`.
2. **PUBLIC versus IN_VPC.** Set `dns_resolution = "PUBLIC"`. Terraform plans to **replace** the resource gateway (the property is immutable), and a public resolver cannot read `svc.internal`, so the target is unreachable. Switch back to `IN_VPC`.
3. **Address change with no Lattice edit.** Point the A record at a different target (`create_instances = false`, `target_ip = ...`). Only the record changes; the resource configuration does not. Keep the old address serving until resolver caches expire.
4. **Owner-side switch.** Set `private_dns_enabled = false` on the resource association and observe that no consumer gets a hosted zone.

## Things this lab does not show

- Cross-account sharing. In production you share the service network (or the resource configuration) with AWS RAM, and the consumer account accepts the share before it creates its VPC association. Everything else is identical.
- On-premises DNS. Pattern 2 in the lesson uses a Route 53 Resolver FORWARD rule and an outbound endpoint in the producer VPC; for the same name, a Resolver rule takes precedence over a private hosted zone.

## Constraints to remember (IN_VPC)

- Cannot host ARN resource configurations (for example an RDS database by ARN); use a separate PUBLIC resource gateway in the same subnets.
- Cannot use IPv6-only subnets; use IPv4 or dual-stack.
- Domain-name targets are TCP only (`TCP_UDP` is rejected).
- DNS queries use UDP only, with no TCP fallback; responses larger than 8,400 bytes fail. The resolver must be recursive and return the records a CNAME points to.
- A DNS server change in the VPC's DHCP option set takes up to 24 hours to reach the resource gateway.
- CIDR resource configurations require an IN_VPC resource gateway.

## Clean up

```bash
terraform destroy
```

## References

- https://aws.amazon.com/blogs/networking-and-content-delivery/use-private-domain-name-targets-with-amazon-vpc-lattice/
- https://docs.aws.amazon.com/vpc/latest/privatelink/resource-gateway.html
- https://docs.aws.amazon.com/vpc/latest/privatelink/resource-configuration-associations.html
- https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_gateway
