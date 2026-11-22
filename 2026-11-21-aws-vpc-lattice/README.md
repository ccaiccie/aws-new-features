# Amazon VPC Lattice Practice Lab (Service-to-Service, Auth Policies, & AWS RAM)

This Terraform lab accompanies the **Network Technician** YouTube lesson on **Amazon VPC Lattice** (service-to-service connectivity, service network VPC endpoints, TLS passthrough, and cross-account sharing with AWS RAM).

## What This Lab Creates

- **VPC & Private Subnets**: A self-contained `10.42.0.0/16` VPC with two private subnets and a security group for VPC Lattice traffic.
- **VPC Lattice Service Network** (`aws_vpclattice_service_network`) with `auth_type = "AWS_IAM"`.
- **VPC Association** (`aws_vpclattice_service_network_vpc_association`) attaching the lab VPC to the service network.
- **VPC Lattice Service** (`aws_vpclattice_service`) associated with the service network.
- **Two IP Target Groups** (`orders-v1` and `orders-v2`) with HTTP `/health` checks.
- **HTTPS Listener & Path Rule** (`aws_vpclattice_listener` and `aws_vpclattice_listener_rule`) demonstrating 90/10 weighted routing on the default action plus a `/v2/` prefix rule.
- **Defense-in-Depth Auth Policies** (`aws_vpclattice_auth_policy`) on both the service network and the `orders` service.
- **Access Log Subscription** (`aws_vpclattice_access_log_subscription`) streaming service network access logs to Amazon CloudWatch Logs.
- **Optional AWS RAM Sharing** (`aws_ram_resource_share` + associations) toggled via `enable_ram_share = true`.

## Usage

```bash
terraform init
terraform validate
terraform plan
```

To deploy into your AWS account:

```bash
terraform apply
```

To clean up all lab resources:

```bash
terraform destroy
```

## Provider & Lab Scope Notes (Honest Gaps)

- **Service Network VPC Endpoints (`ServiceNetwork` type)**: AWS PrivateLink supports interface VPC endpoints of type `ServiceNetwork` (`service_network_arn` on `aws_vpc_endpoint`) so a single VPC can reach multiple service networks, or so on-premises and cross-Region clients can reach a service network. Because a single VPC cannot simultaneously hold both a VPC association and a service network VPC endpoint for the *same* service network without careful routing separation, this lab demonstrates the standard VPC association and leaves the `ServiceNetwork` endpoint as an architectural extension.
- **TLS Passthrough (`TLS_PASSTHROUGH`)**: TLS passthrough in VPC Lattice requires a verified custom domain name on the `aws_vpclattice_service`, a `TCP` target group, and a `TLS_PASSTHROUGH` listener with only a default forward action (no Layer 7 path/header rules and no IAM principal inspection). Because a real custom domain and backend workload TLS certificates are environment-specific, the lab deploys an HTTPS listener with weighted HTTP rules so it validates and applies cleanly out of the box.
- **Targets**: No EC2 instances or containers are registered into the `IP` target groups in this base lab to avoid ongoing compute charges; register your own private IPs or attach ECS/EKS workloads when testing live traffic.
