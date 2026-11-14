output "vpc_id" {
  value = aws_vpc.lab.id
}

output "primary_profile_id" {
  value = aws_route53profiles_profile.primary.id
}

output "secondary_profile_id" {
  value = aws_route53profiles_profile.secondary.id
}

output "primary_association_id" {
  value = aws_route53profiles_association.primary.id
}

output "primary_zone_id" {
  value = aws_route53_zone.primary.zone_id
}

output "secondary_zone_id" {
  value = aws_route53_zone.secondary.zone_id
}
