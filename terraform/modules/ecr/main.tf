################################################################################
# ECR Module — Private Container Registry
#
# Amazon ECR stores Docker images for the platform. Every image deployed
# to EKS is pulled from here — never from public Docker Hub in production.
#
# WHY PRIVATE REGISTRY?
# - Security: You control what runs in your cluster (no supply-chain attacks)
# - Speed: ECR is in the same region as EKS — sub-second image pulls
# - Scanning: Trivy/ECR scan images for CVEs on every push
# - Immutability: Tag immutability prevents overwriting a tagged image
#   (e.g., v1.2.3 always points to the same digest)
#
# LIFECYCLE POLICY:
# Untagged images (failed builds, intermediate layers) are automatically
# deleted after 7 days. This prevents unbounded storage cost growth.
# Tagged images are kept indefinitely (they represent releases).
#
# IMAGE FLOW:
# Developer → Git Push → GitHub Actions → docker build → docker push to ECR
#          → Trivy scans for CVEs → Cosign signs the image
#          → ArgoCD deploys → EKS pulls from ECR (verified by Kyverno)
################################################################################

#===============================================================================
# ECR Repositories
# One repository per service/application. We create repos for:
# - Platform demo app (demonstrates the full pipeline)
# - Edge workloads (deployed to k3s via ArgoCD)
#===============================================================================

resource "aws_ecr_repository" "repositories" {
  for_each = toset(var.repository_names)

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "IMMUTABLE"  # Once a tag is pushed, it can't be overwritten

  # Scan every image on push for known vulnerabilities (CVEs)
  # Results available in ECR console and via API
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encrypt images at rest using AES-256 (AWS-managed key)
  # For CMK encryption, use encryption_configuration with kms_key
  encryption_configuration {
    encryption_type = "AES256"
  }

  # Force delete even if images exist (needed for clean terraform destroy)
  force_delete = true

  tags = {
    Name = "${var.project_name}-ecr-${each.value}-${var.environment}"
  }
}

#===============================================================================
# Lifecycle Policy
# Automatically cleans up untagged images after 7 days.
# This prevents storage costs from growing indefinitely with every CI build.
#
# Rules:
# 1. Untagged images older than 7 days → deleted
# 2. Keep only the last 20 tagged images (older releases are removed)
#
# In production with compliance requirements, you might keep more or
# archive to S3 Glacier, but for this platform 20 releases is sufficient.
#===============================================================================

resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each = aws_ecr_repository.repositories

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
