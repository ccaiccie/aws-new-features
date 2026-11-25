# AWS Transit Gateway context sharing: prove inspection and a context rule hit

> **Billable sandbox lab.** Applying the plan creates a Transit Gateway and attachments, a two-AZ AWS Network Firewall, two EC2 instances and CloudWatch logs. Check [Transit Gateway pricing](https://aws.amazon.com/transit-gateway/pricing/) and [Network Firewall pricing](https://aws.amazon.com/network-firewall/pricing/) before applying. Use a disposable AWS account/Region and tear down when finished. This permissive lab policy is not a production baseline. The packet exercise below is a runbook with **expected** results, not an AWS execution record.

## What you build and why

- Terraform builds the Dev and Prod spokes, two private test hosts, the AWS-managed firewall attachment, bidirectional steering and CloudWatch **FLOW** and **ALERT** logs. The Prod host runs the same private HTTP responder on TCP 8080–8082. There is no public IP, NAT or internet gateway. SSH to Dev uses an IAM-authorized VPC-local EC2 Instance Connect Endpoint, not the inspection path.
- TGW context sharing adds the **sender's AWS resource identity** to each inspected packet. Network Firewall can match that identity instead of an IP range alone. The firewall infers the destination from the reply. In TCP a destination-context rule starts matching only **after** the handshake; a destination-context allow cannot by itself open a handshake that another rule or the default action drops.
- Network Manager's context store, its association, the account-level IAM role and the extra context rule are manual in this example. Terraform manages the baseline only. You can prove inspection on day one without the context store, but cannot claim a context match until Phase 2.

### Packet path

| Packet | Source subnet route | TGW lookup before inspection | TGW lookup after inspection |
|---|---|---|---|
| Dev client → Prod server | Prod CIDR → TGW | Dev attachment selects **before-inspection**; Prod CIDR → firewall attachment | Firewall attachment selects **after-inspection**; Prod CIDR → Prod attachment |
| Prod reply → Dev client | Dev CIDR → TGW | Prod attachment selects **before-inspection**; Dev CIDR → same firewall attachment | Firewall attachment selects **after-inspection**; Dev CIDR → Dev attachment |

The firewall attachment uses appliance mode automatically. The spoke CIDRs are deliberately **not** propagated into the pre-inspection table. Instead each lookup uses an explicit static route. The VPC local route delivers packets leaving TGW to the target instance. See [AWS network-function routing](https://docs.aws.amazon.com/vpc/latest/tgw/route-traffic-nf-attachment.html) and [TGW-attached firewall considerations](https://docs.aws.amazon.com/network-firewall/latest/developerguide/tgw-firewall-considerations.html).

## 1. Prerequisites and preflight

Install [Terraform](https://developer.hashicorp.com/terraform/install) 1.7+ and [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), with OpenSSH in your PATH. The AWS provider lock selects 6.73.0. Use a sandbox operator allowed to manage the resources described above, read the public SSM AMI parameter, configure CloudWatch log delivery (including the requisite Logs delivery/resource-policy permissions), and use EC2 Instance Connect (`SendSSHPublicKey` and `OpenTunnel` plus EC2 discovery). IAM setup for context sharing is described separately below. Choose a Region where both firewall attachment and context sharing are available, with two ordinary AZs and capacity for t3.micro. Default is `us-east-1`; use the same Region throughout.

```bash
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 AWS_PAGER=""
aws sts get-caller-identity
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var "aws_region=$AWS_REGION" -out=lab.tfplan
```

- `get-caller-identity` shows the AWS account that would incur charges. Check it first.
- `init` installs the locked provider; `fmt -check` and `validate` check files and schema; `plan` consults AWS and saves the proposed changes without provisioning. Inspect the plan for the two EC2 instances, firewall, and four TGW static routes. If moving from the original scaffolding, review the changed associations and firewall rules before proceeding; preferably use a fresh sandbox and state.
- Only if you intend to incur sandbox charges, run `terraform apply lab.tfplan` to apply the reviewed plan.

For an offline plan check after `init`, run `terraform test`. The included test uses a mocked AWS provider and checks both route directions, association counts, private hosts and the log types. It does not call AWS or verify packet behavior.

## 2. Verify the routes and prove basic firewall inspection

Use actual IDs from Terraform state. The association queries show which table an arriving packet uses. The static route queries show its selected next hop.

```bash
PRE=$(terraform output -raw before_inspection_table_id)
POST=$(terraform output -raw after_inspection_table_id)
FW=$(terraform output -raw network_firewall_arn)
for TABLE in "$PRE" "$POST"; do
  aws ec2 get-transit-gateway-route-table-associations --transit-gateway-route-table-id "$TABLE"
  aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id "$TABLE" \
    --filters Name=type,Values=static
done
aws network-firewall describe-firewall --firewall-arn "$FW" \
  --query 'FirewallStatus.{Status:Status,Config:ConfigurationSyncStateSummary,TGW:TransitGatewayAttachmentSyncState}'
aws network-firewall describe-logging-configuration --firewall-arn "$FW"
terraform output -raw server_private_ip
```

Check two spoke associations on the before table and only the firewall association on the after table. Both static before routes must be active with the same firewall attachment ID. Each after route must be active with the appropriate spoke attachment ID. Check that the firewall is ready, configuration is in sync, and both log destinations exist. If the paths differ from the table above, stop and troubleshoot before interpreting a timeout.

In a second terminal, from the same Terraform directory, use this command to open a private shell on the Dev client:

```bash
aws ec2-instance-connect ssh --region us-east-1 --connection-type eice \
  --instance-id "$(terraform output -raw client_instance_id)" \
  --eice-options "endpointId=$(terraform output -raw ssh_endpoint_id)" --os-user ec2-user
```

Replace `us-east-1` if necessary. This uses an ephemeral SSH key and the private endpoint; it does not open public SSH. Inside the Dev shell, set `SERVER` to the printed Prod private IP:

```bash
SERVER=REPLACE_WITH_PROD_PRIVATE_IP
date -u
probe() {
  curl --noproxy '*' --trace-time -v --connect-timeout 4 --max-time 8 \
    "http://$SERVER:$1/$2"
}
probe 8080 control
probe 8081 context
probe 8082 control
```

Expected: 8080 and 8081 return HTTP 200 and the responder's fixed text. 8082 never establishes TCP because the IP-based baseline rule drops traffic to that port (SID **100001**). The server listens and the security group admits all three ports from the Dev test subnet. No broad Dev → Prod firewall rule masks the context test. The firewall leaves other unmatched traffic permitted in this isolated lab. A timeout alone is not evidence: confirm SID 100001 in ALERT and the 8080/8081 sessions in FLOW.

## 3. Enable resource context and demonstrate post-handshake matching

1. In **Network Manager → Global networks**, open the global network from `terraform output -raw global_network_id`. Wait for the registered TGW to be **Available**. In **Context store**, create a lab-only store and select the lab TGW from `terraform output -raw transit_gateway_id`. Wait for the store to be **Available** and the association **Associated**.
2. In the store owner account, use the existing compatible `NetworkFirewallContextStoreReadOnly` IAM role, or have the sandbox IAM admin create it once. The [AWS onboarding guide](https://docs.aws.amazon.com/network-firewall/latest/developerguide/context-aware-rules-setup.html) specifies its exact service trust and four read permissions. This fixed-name role applies to all stores in that account. Do not replace or later delete a shared role.
3. Verify Network Firewall discovers the store. These are read-only commands. The VPC listing must include both lab IDs from `terraform output -raw dev_vpc_id` and `terraform output -raw prod_vpc_id`.

```bash
STORE=$(aws network-firewall describe-firewall --firewall-arn "$FW" \
  --query 'Firewall.ContextStoreId' --output text)
printf '%s\n' "$STORE"
# Run this after STORE contains a real context-store ID, not None.
aws network-firewall list-resources-in-context-store --context-store-id "$STORE" \
  --filters "Region=$AWS_REGION,ResourceType=VPC"
```

4. In the VPC console, create a separate **Classic → Stateful → Text rule builder → Strict order** rule group. Create context sets `DEV_CONTEXT` and `PROD_CONTEXT`, selecting the tracked Dev VPC and Prod VPC IDs respectively. They are **Context sets**, not IP sets. Use the rule below, and add the group to the lab policy shown by `terraform output -raw firewall_policy_arn`. Keep the existing baseline group. Wait for firewall configuration to be in sync and the context status to be **Fully resolved**. The policy attachment is a temporary console change Terraform does not track; do not re-apply the Terraform plan with the manual group attached.

```suricata
alert http $DEV_CONTEXT any -> $PROD_CONTEXT 8081 (flow:established,to_server; http.uri; content:"/context"; startswith; endswith; msg:"Lab Dev to Prod resource context"; sid:100010; rev:1;)
```

`alert` records a hit without terminating the connection. `http` and `flow:established,to_server` require a client request on an established connection. The two context variables constrain the AWS identity at each end; the port and exact URI give you a positive and a negative test on the same listener. The SID makes the rule easy to find.

5. On Dev, run `date -u; probe 8081 context; probe 8081 control` again in fresh TCP sessions. Both should return 200 in monitor mode; only `/context` should log SID **100010**. Then, optionally, change `alert` to `drop` and `rev:1` to `rev:2` in the manual group, wait for sync, and repeat. The `/context` probe should print `Connected` (TCP handshake succeeded) but not return HTTP 200. The `/control` probe should still return 200. The IP-only 8082 block remains unchanged. For packet-level evidence, if tcpdump is already available, capture on Dev during the probes with `sudo tcpdump -ni any -nn "host $SERVER and tcp port 8081"` and identify SYN, SYN-ACK, ACK and subsequent client request. Do not treat the command's output as evidence of an identity match without the firewall logs.

### Read and correlate the actual log records

In the Terraform terminal, read the lab-specific groups. Increase the time window or allow for ingestion/flow-record delay if necessary.

```bash
aws logs tail "$(terraform output -raw alert_log_group)" --since 20m --format short
aws logs tail "$(terraform output -raw flow_log_group)" --since 20m --format short
```

Find the probe's alert by timestamp, addresses, ports and `event.alert.signature_id`. For the context rule, check `event.context.matched` for the referenced AWS IDs. Find the same `event.flow_id` in FLOW and check `event.context.src` for Dev and the learned `event.context.dst` for Prod. The one-way IP drop can have no destination context. A FLOW record with resource IDs alone proves metadata arrived, not that your rule matched. If the 8080 control fails, check TGW route tables, the server startup and security groups first. If 8081 passes but has no context alert, check the context association, IAM role, fully resolved IDs, rule attachment and log delivery.

AWS references: [context rule syntax](https://docs.aws.amazon.com/network-firewall/latest/developerguide/context-aware-rules-writing.html), [destination timing](https://docs.aws.amazon.com/network-firewall/latest/developerguide/context-aware-rules-destination.html), [log fields](https://docs.aws.amazon.com/network-firewall/latest/developerguide/context-aware-rules-logging.html).

## 4. Roll back and tear down

To undo only the context experiment, detach the manually added group, keep the Terraform baseline group, and re-run the Phase 1 probes. Before tearing down, export any needed logs. Delete the detached manual group; disassociate the lab TGW from the store, wait until the association is gone, and delete the lab-only context store. Preserve a shared IAM role. If the lab was applied, use the same account, Region and Terraform state:

```bash
terraform plan -destroy -var "aws_region=$AWS_REGION" -out=destroy.tfplan
# Review that this plan only removes lab resources, then:
terraform apply destroy.tfplan
terraform state list
```

The destroy plan reverses the provisioned resources, including the TGW, firewall, endpoints, VMs and log groups. An empty state is not a billing check: confirm the lab firewall, attachments and instances are gone in AWS, and check for any manually created objects. Do not delete shared logging policies or IAM roles.

## Links

[Courses](https://learn.techtohire.com) · [Free Daily Quiz](https://quiz.techtohire.com) · [Website](https://www.techtohire.com)
