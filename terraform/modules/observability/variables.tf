################################################################################
# Observability Module — Input Variables
################################################################################

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, staging)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used in log group paths"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting log groups at rest"
  type        = string
}
