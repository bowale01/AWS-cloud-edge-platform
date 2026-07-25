################################################################################
# Bootstrap — S3 Bucket + DynamoDB Table for Terraform Remote State
#
# This is a standalone Terraform configuration that creates the backend
# infrastructure BEFORE the main project can use it.
#
# WHY A SEPARATE FOLDER?
# Chicken-and-egg problem: Terraform needs an S3 bucket to store state,
# but you can't use Terraform to create that bucket if it doesn't have
# state storage yet. Solution: this bootstrap uses LOCAL state to create
# the S3 bucket and DynamoDB table, then the main project uses those
# resources as its remote backend.
#
# HOW TO USE:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#   cd ..
#   terraform init    <-- this now connects to the S3 backend
#
# This only needs to run ONCE. After that, never touch it again unless
# you're tearing down the entire project (destroy main infra first,
# then destroy bootstrap last).
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "rockauto"
      Environment = "prod"
      ManagedBy   = "terraform"
      Purpose     = "terraform-state-backend"
    }
  }
}

################################################################################
# S3 Bucket — Stores the Terraform State File
#
# The state file contains a full map of every resource Terraform manages,
# including sensitive values like database passwords and ARNs.
# That's why we enable:
# - Versioning: Roll back if state gets corrupted
# - Encryption: Protect secrets at rest with AWS KMS
# - Public access block: State should NEVER be public
################################################################################

resource "aws_s3_bucket" "terraform_state" {
  bucket = "rockauto-terraform-state-prod"

  # Prevent accidental deletion of this bucket (contains all state history)
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "rockauto-terraform-state-prod"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# DynamoDB Table — State Locking
#
# When someone runs `terraform apply`, Terraform acquires a lock in this table.
# If another person (or CI pipeline) tries to apply at the same time, they get
# a "state locked" error instead of corrupting the state file.
#
# PAY_PER_REQUEST billing = you only pay when locks are acquired/released.
# For Terraform usage, this costs essentially $0 (a few requests per day).
################################################################################

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "rockauto-terraform-locks-prod"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "rockauto-terraform-locks-prod"
  }
}

################################################################################
# Outputs — Confirm what was created
################################################################################

output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}
