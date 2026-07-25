################################################################################
# ECR Module — Outputs
# These URLs are used in CI/CD pipelines (docker push) and Kubernetes
# manifests (image: <url>:<tag>)
################################################################################

output "repository_urls" {
  description = "Map of repository names to their ECR URLs (use in docker push and K8s manifests)"
  value = {
    for name, repo in aws_ecr_repository.repositories :
    name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository names to their ARNs (use in IAM policies)"
  value = {
    for name, repo in aws_ecr_repository.repositories :
    name => repo.arn
  }
}

output "registry_id" {
  description = "ECR registry ID (AWS account ID) — used in docker login command"
  value       = values(aws_ecr_repository.repositories)[0].registry_id
}
