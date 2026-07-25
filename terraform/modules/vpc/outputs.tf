################################################################################
# VPC Module — Outputs
# These values are consumed by other modules (EKS needs subnet IDs,
# Edge module needs VPC ID for peering, etc.)
################################################################################

output "vpc_id" {
  description = "ID of the platform VPC"
  value       = aws_vpc.platform.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the platform VPC"
  value       = aws_vpc.platform.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (ALB, NAT Gateway)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (EKS worker nodes)"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways (one per AZ)"
  value       = aws_nat_gateway.platform[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.platform.id
}
