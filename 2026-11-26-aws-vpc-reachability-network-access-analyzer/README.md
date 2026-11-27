# Amazon VPC Reachability Analyzer & Network Access Analyzer Lab

A small, disposable Terraform + AWS CLI practice lab that demonstrates:

1. **Reachability Analyzer (Working Path):** `web` -> `app` over TCP port `443` (produces hop-by-hop virtual network path details).
2. **Reachability Analyzer (Blocked Path):** `app` -> `db` over TCP port `5432` (identifies the missing security group inbound rule with explanation code `ENI_SG_RULES_MISMATCH`).
3. **Network Access Analyzer (Unexpected Internet Access):** A Network Access Scope that matches inbound paths from an Internet Gateway to the lab VPC while excluding TCP port `443`, surfacing the unintended TCP port `22` exposure on the `web` instance.

> **Cost Warning:** Analyses are billed when you run them (Reachability Analyzer is billed per analysis run; Network Access Analyzer is billed per EC2 Elastic Network Interface analyzed), and lab EC2 instances (and any NAT gateways if you add them) bill until deleted. Always destroy every resource when finished. Check current regional rates under the **Network Analysis** tab on the [Amazon VPC Pricing](https://aws.amazon.com/vpc/pricing/) page.

## Official AWS Documentation

- [What is Reachability Analyzer?](https://docs.aws.amazon.com/vpc/latest/reachability/what-is-reachability-analyzer.html)
- [How Reachability Analyzer works](https://docs.aws.amazon.com/vpc/latest/reachability/how-reachability-analyzer-works.html)
- [Getting started with Reachability Analyzer (Console)](https://docs.aws.amazon.com/vpc/latest/reachability/getting-started.html)
- [Getting started with Reachability Analyzer (AWS CLI)](https://docs.aws.amazon.com/vpc/latest/reachability/getting-started-cli.html)
- [What is Network Access Analyzer?](https://docs.aws.amazon.com/vpc/latest/network-access-analyzer/what-is-network-access-analyzer.html)
- [How Network Access Analyzer works](https://docs.aws.amazon.com/vpc/latest/network-access-analyzer/how-network-access-analyzer-works.html)
- [Getting started with Network Access Analyzer (AWS CLI)](https://docs.aws.amazon.com/vpc/latest/network-access-analyzer/getting-started-cli.html)
- [Example Network Access Scopes](https://docs.aws.amazon.com/vpc/latest/network-access-analyzer/example-scopes.html)
- [Amazon VPC Pricing (Network Analysis tab)](https://aws.amazon.com/vpc/pricing/)

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI v2 configured with permissions for EC2, VPC, Reachability Analyzer (`ec2:*NetworkInsightsPath*`, `ec2:*NetworkInsightsAnalysis*`), and Network Access Analyzer (`ec2:*NetworkInsightsAccessScope*`).

## 1. Deploy the Disposable VPC

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

By default, `run_reachability_analyses = false` so `terraform apply` creates the VPC, subnets, security groups, three `t3.micro` instances, and two Reachability Analyzer path definitions without running paid analyses yet.

## 2. Run Reachability Analyzer & Network Access Analyzer via AWS CLI

```bash
chmod +x run-analyses.sh cleanup.sh
./run-analyses.sh
```

What you will observe:
- **Working path (`web` -> `app`, TCP 443):** `NetworkPathFound: true` with `ForwardPathComponents` listing the source instance, ENI, security groups, subnets, network ACLs, route table, destination ENI, and destination instance.
- **Blocked path (`app` -> `db`, TCP 5432):** `NetworkPathFound: false` with `Explanations` containing `ExplanationCode: "ENI_SG_RULES_MISMATCH"` pointing at the destination security group.
- **Network Access Analyzer Scope:** `FindingsFound: "true"` and `AnalysisFindings` showing the inbound path from `AWS::EC2::InternetGateway` to the `web` instance on TCP port `22` (while port `443` was excluded by `ExcludePaths`).

## 3. Tear Down & Destroy Every Resource

Delete the CLI-created Network Access Scope, analyses, and destroy the Terraform-managed VPC and instances:

```bash
export SCOPE_ID="nis-..."
export NAA_ANALYSIS_ID="nisa-..."
export WORK_ANALYSIS_ID="nia-..."
export BLOCK_ANALYSIS_ID="nia-..."
./cleanup.sh
```

Or run the commands manually:

```bash
aws ec2 delete-network-insights-access-scope-analysis --network-insights-access-scope-analysis-id "$NAA_ANALYSIS_ID"
aws ec2 delete-network-insights-access-scope --network-insights-access-scope-id "$SCOPE_ID"
aws ec2 delete-network-insights-analysis --network-insights-analysis-id "$WORK_ANALYSIS_ID"
aws ec2 delete-network-insights-analysis --network-insights-analysis-id "$BLOCK_ANALYSIS_ID"
terraform destroy
```

Verify in the AWS Console (EC2 -> Instances, VPC -> Network Manager -> Reachability Analyzer / Network Access Analyzer) that no lab instances, paths, scopes, or analyses remain.
