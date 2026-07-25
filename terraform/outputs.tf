################################################################################
# Outputs — Values Exposed After Terraform Apply
#
# Outputs serve three purposes:
# 1. Display useful info after `terraform apply` (cluster endpoint, ECR URL)
# 2. Allow other Terraform configurations to consume these values via
#    `terraform_remote_state` data source (cross-project references)
# 3. Provide values needed for kubectl, Helm, and CI/CD configuration
#
# After running `terraform apply`, you'll see these printed in the terminal.
# You can also retrieve them anytime with: terraform output <name>
################################################################################

#===============================================================================
# EKS Cluster Outputs
# These are needed to configure kubectl and connect to the cluster.
# Run: aws eks update-kubeconfig --name <cluster_name> --region us-east-1
#===============================================================================

output "cluster_name" {
  description = "EKS cluster name — use with: aws eks update-kubeconfig --name <this>"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint — where kubectl sends requests"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA cert for the cluster — used to verify the API server's TLS certificate"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — needed when creating IRSA roles for platform services (ArgoCD, External Secrets, etc.)"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL — the issuer URL used in IAM trust policies for IRSA"
  value       = module.eks.oidc_provider_url
}

#===============================================================================
# Networking Outputs
# Useful for debugging connectivity issues or adding new resources to the VPC.
#===============================================================================

output "vpc_id" {
  description = "Platform VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs where EKS worker nodes run"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs where ALB and NAT Gateway live"
  value       = module.vpc.public_subnet_ids
}

#===============================================================================
# ECR Outputs
# The registry URL is needed in CI/CD pipelines to push and pull images.
# Format: <account_id>.dkr.ecr.<region>.amazonaws.com/<repo_name>
#===============================================================================

output "ecr_repository_urls" {
  description = "ECR repository URLs — use in Dockerfiles and Kubernetes manifests for image references"
  value       = module.ecr.repository_urls
}

#===============================================================================
# Security Outputs
#===============================================================================

output "kms_key_arn" {
  description = "KMS key ARN used for encrypting EKS secrets, EBS volumes, and CloudWatch logs"
  value       = module.security.kms_key_arn
}

#===============================================================================
# Edge Outputs
#===============================================================================

output "edge_vpc_id" {
  description = "Edge VPC ID — the simulated factory-floor network"
  value       = module.edge.edge_vpc_id
}

output "edge_instance_public_ip" {
  description = "Public IP of the edge k3s node"
  value       = module.edge.edge_instance_public_ip
}

output "edge_ssm_connect" {
  description = "Connect to edge node via SSM (no SSH keys, fully audited)"
  value       = module.edge.ssm_connect_command
}

output "vpc_peering_connection_id" {
  description = "VPC peering connection between platform and edge VPCs"
  value       = module.edge.vpc_peering_connection_id
}

#===============================================================================
# Quick Start Commands (printed after apply)
#===============================================================================

output "configure_kubectl" {
  description = "Run this command to configure kubectl for the new cluster"
  value       = "aws eks update-kubeconfig --name ${local.cluster_name} --region ${var.aws_region}"
}
