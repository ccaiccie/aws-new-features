output "aws_region" {
  description = "Local AWS Region for this lab."
  value       = var.aws_region
}

output "vpc_id" {
  description = "AWS VPC ID."
  value       = aws_vpc.lab.id
}

output "transit_gateway_id" {
  description = "Local-Region Transit Gateway ID."
  value       = aws_ec2_transit_gateway.lab.id
}

output "direct_connect_gateway_id" {
  description = "Direct Connect gateway ID (use this as --attach-point directConnectGateway=<ID> in AWS CLI)."
  value       = aws_dx_gateway.lab.id
}

output "cli_next_step" {
  description = "Opt-in AWS CLI guidance for creating or accepting the AWS Interconnect."
  value = var.enable_interconnect_cli_instructions ? (
    "OPT-IN ENABLED (BILLED): Run 'aws interconnect list-environments --region ${var.aws_region}' to find the Microsoft Azure environment-id, then run 'aws interconnect create-connection --region ${var.aws_region} --description \"${var.name_prefix}\" --bandwidth 1Gbps --attach-point directConnectGateway=${aws_dx_gateway.lab.id} --environment-id <ENV_ID> --remote-account identifier=<AZURE_ID>' or 'aws interconnect accept-connection-proposal --region ${var.aws_region} --attach-point directConnectGateway=${aws_dx_gateway.lab.id} --activation-key <ACTIVATION_KEY>'."
  ) : (
    "SAFE DEFAULT: Interconnect creation is NOT enabled. Set enable_interconnect_cli_instructions = true only when you are ready to incur hourly charges and follow the README destroy steps."
  )
}
