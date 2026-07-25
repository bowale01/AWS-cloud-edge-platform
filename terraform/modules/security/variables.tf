################################################################################
# Security Module — Input Variables
################################################################################

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, staging)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used in KMS key policy to grant account-level access"
  type        = string
}
