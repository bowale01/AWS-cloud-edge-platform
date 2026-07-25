################################################################################
# Security Module — Outputs
################################################################################

output "kms_key_arn" {
  description = "ARN of the platform KMS key — used by EKS, EBS, CloudWatch for encryption"
  value       = aws_kms_key.platform.arn
}

output "kms_key_id" {
  description = "ID of the platform KMS key"
  value       = aws_kms_key.platform.key_id
}

output "kms_alias_name" {
  description = "KMS key alias for easy reference"
  value       = aws_kms_alias.platform.name
}

output "secrets_manager_arn" {
  description = "ARN of the app secrets in Secrets Manager"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "secrets_manager_name" {
  description = "Name of the app secrets in Secrets Manager"
  value       = aws_secretsmanager_secret.app_secrets.name
}

output "external_secrets_policy_arn" {
  description = "IAM policy ARN for External Secrets Operator — attach to ESO's IRSA role"
  value       = aws_iam_policy.external_secrets.arn
}
