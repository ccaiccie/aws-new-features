output "vpc_id" {
  description = "Disposable lab VPC ID."
  value       = aws_vpc.lab.id
}

output "source_instance_id" {
  description = "EC2 instance ID of the Traffic Mirroring source."
  value       = aws_instance.source.id
}

output "source_eni_id" {
  description = "Primary ENI ID of the source instance."
  value       = aws_instance.source.primary_network_interface_id
}

output "source_private_ip" {
  description = "Primary private IPv4 address of the source ENI (appears as the outer VXLAN source IP)."
  value       = aws_instance.source.private_ip
}

output "source_public_ip" {
  description = "Public IPv4 address of the source instance."
  value       = aws_instance.source.public_ip
}

output "target_instance_id" {
  description = "EC2 instance ID of the monitoring target appliance."
  value       = aws_instance.target.id
}

output "target_eni_id" {
  description = "Primary ENI ID of the monitoring target appliance."
  value       = aws_instance.target.primary_network_interface_id
}

output "target_public_ip" {
  description = "Public IPv4 address of the monitoring target appliance."
  value       = aws_instance.target.public_ip
}

output "traffic_mirror_target_id" {
  description = "Traffic Mirror Target ID."
  value       = aws_ec2_traffic_mirror_target.appliance.id
}

output "traffic_mirror_filter_id" {
  description = "Traffic Mirror Filter ID."
  value       = aws_ec2_traffic_mirror_filter.web_only.id
}

output "traffic_mirror_session_id" {
  description = "Traffic Mirror Session ID (billed hourly until deleted)."
  value       = aws_ec2_traffic_mirror_session.lab.id
}
