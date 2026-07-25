################################################################################
# Terraform Backend — Remote State in S3
#
# State is stored remotely in S3 with DynamoDB locking. This is the
# production-grade pattern because:
# - S3 provides durability (99.999999999%), versioning, and encryption at rest
# - DynamoDB provides state locking — prevents two people (or CI pipelines)
#   from running `terraform apply` simultaneously and corrupting state
# - Encryption ensures sensitive values in state (like passwords, ARNs) are
#   protected at rest using AWS KMS
#
# IMPORTANT: The S3 bucket and DynamoDB table must exist BEFORE running
# `terraform init`. Create them with these commands (one-time setup):
#
#   aws s3api create-bucket \
#     --bucket rockauto-terraform-state-prod \
#     --region us-east-1
#
#   aws s3api put-bucket-versioning \
#     --bucket rockauto-terraform-state-prod \
#     --versioning-configuration Status=Enabled
#
#   aws s3api put-bucket-encryption \
#     --bucket rockauto-terraform-state-prod \
#     --server-side-encryption-configuration \
#       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
#
#   aws s3api put-public-access-block \
#     --bucket rockauto-terraform-state-prod \
#     --public-access-block-configuration \
#       BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
#
#   aws dynamodb create-table \
#     --table-name rockauto-terraform-locks-prod \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST
################################################################################

terraform {
  backend "s3" {
    bucket         = "rockauto-terraform-state-prod"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "rockauto-terraform-locks-prod"
    encrypt        = true
  }
}
