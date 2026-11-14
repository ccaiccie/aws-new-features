# Route 53 Profiles, more than one profile per VPC

Terraform practice lab for this video: https://youtu.be/ZTmhV3bcwSA

## Goals

- Create two Route 53 Profiles and a VPC
- Attach a private hosted zone to each profile
- Associate the primary profile to the VPC with Terraform
- Associate the secondary profile with the AWS CLI, setting a unique priority, which is the November 9, 2026 change the lesson covers

## Prerequisites

- An AWS account and credentials (`aws configure` or environment variables) plus `terraform` 1.6+
- IAM permissions for the services in this folder

## Cost warning

A Route 53 Profile-VPC association is billed per association. Each private hosted zone has a small monthly charge. This lab creates one VPC (no NAT gateways or instances) and two associations only if you also run the CLI step. Destroy the lab when you finish.

## What this lab cannot provision

`aws_route53profiles_association` in AWS provider 6.73.0 accepts `name`, `profile_id`, `resource_id`, and `tags`. It does not have a `priority` argument. The AssociateProfile API uses priority 100–9900 (lower number first, unique per VPC), and the current documentation allows up to two profiles on one VPC.

Terraform therefore associates only the first profile here. Adding a second `aws_route53profiles_association` without a unique priority would likely fail or be ambiguous, so this lab does not invent a priority field.

## Steps

1. Copy the example variables and edit them:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Initialize and review the plan:

   ```bash
   terraform init
   terraform plan
   ```

3. Apply only after you have read the cost warning:

   ```bash
   terraform apply
   ```

After `terraform apply`, associate the second profile with a lower-precedence priority (for example 200; the first association defaults to 100 unless you change it):

```bash
aws route53profiles associate-profile   --name r53prof-lab-secondary-assoc   --profile-id "$(terraform output -raw secondary_profile_id)"   --resource-id "$(terraform output -raw vpc_id)"   --priority 200   --region us-east-1
```

If the CLI flag name differs in your CLI version, see `aws route53profiles associate-profile help` and [AssociateProfile](https://docs.aws.amazon.com/Route53/latest/APIReference/API_route53profiles_AssociateProfile.html).

List associations:

```bash
aws route53profiles list-profile-associations --resource-id "$(terraform output -raw vpc_id)" --region us-east-1
```

Remove the CLI-created association before `terraform destroy` if AWS will not delete the VPC while it remains:

```bash
aws route53profiles disassociate-profile   --profile-id "$(terraform output -raw secondary_profile_id)"   --resource-id "$(terraform output -raw vpc_id)"   --region us-east-1
```

(Use the association ID form of the command if your CLI requires it.)

## Verify

```bash
terraform output
aws route53profiles get-profile --profile-id "$(terraform output -raw primary_profile_id)" --region us-east-1
aws route53profiles list-profile-resource-associations --profile-id "$(terraform output -raw primary_profile_id)" --region us-east-1
aws route53profiles list-profile-associations --resource-id "$(terraform output -raw vpc_id)" --region us-east-1
```

After the CLI step, you should see two associations on the VPC with priorities 100 and 200 (or the values you chose). The lesson's rule is: between profiles, the first matching profile wins even over a more specific rule in the next one.

## Cleanup

Destroy the lab when you are finished so you are not billed for idle resources:

```bash
terraform destroy
```

Confirm in the AWS console that the VPC, profiles, and any firewall endpoints are gone.
