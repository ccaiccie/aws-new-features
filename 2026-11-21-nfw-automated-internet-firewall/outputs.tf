output "vpc_id" {
  value = aws_vpc.lab.id
}

output "expected_igw_firewall_arn" {
  description = "NSM names the firewall after the VPC it protects."
  value       = "arn:aws:network-firewall:${var.region}:${data.aws_caller_identity.current.account_id}:igw-firewall/${aws_vpc.lab.id}"
}

output "public_instance" {
  value = { id = aws_instance.public.id, public_ip = aws_instance.public.public_ip, private_ip = aws_instance.public.private_ip }
}

output "private_instance" {
  value = { id = aws_instance.private.id, private_ip = aws_instance.private.private_ip }
}

output "isolated_subnet_id" {
  value = aws_subnet.isolated.id
}

output "nsm_policy_arn" {
  value = aws_cloudformation_stack.nsm.outputs["PolicyArn"]
}

output "nsm_deployment_arn" {
  value = aws_cloudformation_stack.nsm.outputs["DeploymentArn"]
}

output "policy_mode" {
  value = var.policy_mode
}
