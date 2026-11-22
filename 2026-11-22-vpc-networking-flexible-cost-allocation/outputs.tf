output "vpc_id" {
  description = "ID of the lab VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet hosting the shared NAT gateway."
  value       = aws_subnet.public.id
}

output "team_alpha_private_subnet_id" {
  description = "ID of Team Alpha's private subnet."
  value       = aws_subnet.team_alpha.id
}

output "team_beta_private_subnet_id" {
  description = "ID of Team Beta's private subnet."
  value       = aws_subnet.team_beta.id
}

output "nat_gateway_id" {
  description = "ID of the shared public NAT gateway to associate with an FCA policy."
  value       = aws_nat_gateway.shared.id
}

output "nat_gateway_public_ip" {
  description = "Public IPv4 address allocated to the shared NAT gateway."
  value       = aws_eip.nat.public_ip
}
