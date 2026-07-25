################################################################################
# EKS Module — Outputs
# These are consumed by the root module (providers.tf, outputs.tf) and
# by platform service modules that need cluster connection details.
################################################################################

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.rockauto.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.rockauto.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate for the cluster"
  value       = aws_eks_cluster.rockauto.certificate_authority[0].data
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.rockauto.arn
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "node_group_arn" {
  description = "ARN of the managed node group"
  value       = aws_eks_node_group.rockauto_workers.arn
}

output "node_role_arn" {
  description = "IAM role ARN for worker nodes"
  value       = aws_iam_role.eks_nodes.arn
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — use this when creating IRSA roles for platform services"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL — used in IAM trust policies (strip https:// prefix when using in conditions)"
  value       = aws_eks_cluster.rockauto.identity[0].oidc[0].issuer
}
