################################################################################
# Security Module — KMS Encryption + Secrets Manager
#
# This module implements the encryption and secrets layer for zero-trust:
#
# 1. KMS Key: A customer-managed key (CMK) that encrypts:
#    - EKS etcd secrets (Kubernetes Secrets stored at rest)
#    - EBS volumes attached to worker nodes
#    - CloudWatch log groups
#    - S3 objects (if needed)
#
#    Why CMK instead of AWS-managed keys?
#    - You control rotation policy
#    - You control who can use the key (key policy)
#    - You can audit usage via CloudTrail
#    - You can disable/delete the key to render all data unreadable
#
# 2. Secrets Manager: Stores application secrets (DB passwords, API keys).
#    Pods access these via External Secrets Operator (ESO) — secrets are
#    NEVER stored in Git, ConfigMaps, or environment variables in manifests.
#
# ZERO-TRUST PRINCIPLES APPLIED:
# - Encrypt everything at rest (KMS)
# - No static credentials in code (Secrets Manager + IRSA)
# - Least-privilege access (key policy restricts who can decrypt)
# - Audit trail (CloudTrail logs every KMS API call)
################################################################################

#===============================================================================
# KMS Key — Platform Encryption Key
# A single multi-purpose key for the entire platform. In larger orgs, you
# might have separate keys per service, but one key simplifies management
# and still provides full encryption coverage.
#===============================================================================

resource "aws_kms_key" "platform" {
  description             = "RockAuto platform encryption key for EKS, EBS, CloudWatch, and secrets"
  deletion_window_in_days = 7      # Wait 7 days before permanent deletion (safety net)
  enable_key_rotation     = true   # Automatic annual rotation — no manual intervention needed
  multi_region            = false  # Single region deployment, no need for multi-region key

  # Key policy: who can use this key
  # - Root account has full admin access (required by AWS)
  # - EKS service can use it for envelope encryption
  # - CloudWatch Logs service can use it for log encryption
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.project_name}-platform-key-policy"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEKSServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsEncryption"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-platform-kms-${var.environment}"
  }
}

# Human-readable alias for the key (easier to find in AWS console)
resource "aws_kms_alias" "platform" {
  name          = "alias/${var.project_name}-platform-${var.environment}"
  target_key_id = aws_kms_key.platform.key_id
}

#===============================================================================
# Secrets Manager — Application Secrets Store
#
# Pre-creates a secret "container" that the External Secrets Operator will
# read from. The actual secret values are set manually or via CI/CD — NEVER
# in Terraform code (that would put secrets in state file and Git history).
#
# ESO workflow:
# 1. Secret value stored in Secrets Manager (via CLI or console)
# 2. ExternalSecret CR in Kubernetes references the secret name
# 3. ESO controller fetches value using IRSA credentials
# 4. ESO creates a native Kubernetes Secret in the target namespace
# 5. Pod mounts the Secret as env var or volume
#===============================================================================

resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "${var.project_name}/app-secrets/${var.environment}"
  description = "Application secrets for the RockAuto platform (accessed by External Secrets Operator)"
  kms_key_id  = aws_kms_key.platform.arn  # Encrypt with our CMK, not the default key

  # Force deletion without recovery period (for clean terraform destroy)
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-app-secrets-${var.environment}"
  }
}

# Set a placeholder value — real secrets are updated via CLI:
# aws secretsmanager put-secret-value --secret-id rockauto/app-secrets/prod --secret-string '{"DB_PASSWORD":"xxx"}'
resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    DB_PASSWORD    = "CHANGE_ME_VIA_CLI"
    API_KEY        = "CHANGE_ME_VIA_CLI"
    MQTT_PASSWORD  = "CHANGE_ME_VIA_CLI"
  })

  # Ignore changes because real values are set outside Terraform
  lifecycle {
    ignore_changes = [secret_string]
  }
}

#===============================================================================
# IAM Policy for External Secrets Operator (IRSA)
# This policy will be attached to the ESO service account via IRSA.
# It grants READ-ONLY access to secrets — ESO cannot create or delete them.
#===============================================================================

resource "aws_iam_policy" "external_secrets" {
  name        = "${var.project_name}-external-secrets-policy-${var.environment}"
  description = "Allows External Secrets Operator to read secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = [
          aws_secretsmanager_secret.app_secrets.arn,
          "${aws_secretsmanager_secret.app_secrets.arn}:*"
        ]
      },
      {
        Sid    = "AllowDecryptWithKMS"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.platform.arn]
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-external-secrets-policy-${var.environment}"
  }
}
