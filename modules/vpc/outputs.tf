output "vpc_id" {
  value = aws_vpc.this.id
}

# Convenience: first public & private subnet per AZ (good for ALB / ASG)
output "public_subnet_ids_for_alb" {
  value = [for az in local.azs : aws_subnet.public["${az}-public-0"].id]
}

output "private_subnet_ids_for_asg" {
  value = [for az in local.azs : aws_subnet.private["${az}-private-0"].id]
}

output "ssm_endpoint_id" {
  value = aws_vpc_endpoint.ssm.id
}

output "ssmmessages_endpoint_id" {
  value = aws_vpc_endpoint.ssmmessages.id
}

output "ec2messages_endpoint_id" {
  value = aws_vpc_endpoint.ec2messages.id
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

