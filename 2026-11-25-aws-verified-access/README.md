# Practice Lab — AWS Verified Access with IAM Identity Center & Cedar Policies

Intended repository path: `ccaiccie/aws-new-features/2026-11-25-aws-verified-access`

This Terraform and AWS CLI practice lab deploys an **AWS Verified Access** stack in front of an existing **internal Application Load Balancer (ALB)** using **AWS IAM Identity Center** as the user-identity trust provider and **Cedar** policies at the Verified Access group level.

## Official AWS Documentation Sources
- What is AWS Verified Access?: https://docs.aws.amazon.com/verified-access/latest/ug/what-is-verified-access.html
- Tutorial: Get started with Verified Access: https://docs.aws.amazon.com/verified-access/latest/ug/getting-started.html
- User-identity trust providers: https://docs.aws.amazon.com/verified-access/latest/ug/user-trust.html
- Verified Access policies (Cedar): https://docs.aws.amazon.com/verified-access/latest/ug/auth-policies.html
- Example policies: https://docs.aws.amazon.com/verified-access/latest/ug/trust-data-iam-add-pol.html
- Create a load balancer endpoint: https://docs.aws.amazon.com/verified-access/latest/ug/create-load-balancer-endpoint.html

## Prerequisites
- **AWS Organizations instance of IAM Identity Center** enabled in the **same AWS Region** as this lab (a standalone account instance of IAM Identity Center will **not** work).
- An **internal Application Load Balancer** (IPv4) in your VPC, with its security group allowing traffic from the Verified Access endpoint security group.
- A **public TLS certificate in AWS Certificate Manager (ACM)** matching your `application_domain` (RSA 1,024 or 2,048).
- A public hosted domain where you can add a **CNAME** record pointing `application_domain` to the generated Verified Access `endpoint_domain`.
- **Terraform >= 1.6** and **AWS CLI v2** authenticated to your account.

## Cost Notice
- AWS Verified Access charges **hourly per application** and for **data processed**.
- Run `terraform destroy` as soon as you finish testing to stop hourly charges.

## 1. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
# Fill in your region, internal ALB ARN, subnet IDs (1 per AZ), security group ID,
# application_domain, ACM certificate ARN, and IAM Identity Center group ID.
```

## 2. Deploy in Default-Deny State First
Keep `enable_allow_policy = false` on the first apply to observe Verified Access's default-deny behavior:
```bash
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Create a public DNS **CNAME** record mapping `application_domain` to the `endpoint_domain` output, then open `https://<application_domain>` in your browser — the request is **denied** because no Cedar policy is attached yet.

## 3. Verify with AWS CLI
```bash
aws ec2 describe-verified-access-instances
aws ec2 describe-verified-access-groups
aws ec2 describe-verified-access-endpoints
```

## 4. Enable the Cedar Allow Policy & Re-Test
Set `enable_allow_policy = true` in `terraform.tfvars` and re-apply:
```bash
terraform apply
```
Refresh `https://<application_domain>` in your browser — you are redirected to **IAM Identity Center** to sign in, and once authenticated (member of the allowed group ID with verified email), your request reaches the internal ALB application.

## 5. Destroy & Clean Up
Remove your DNS CNAME record, then run:
```bash
terraform destroy
```
Terraform deletes resources in the required reverse order: endpoint → group → trust provider attachment → trust provider → instance.
