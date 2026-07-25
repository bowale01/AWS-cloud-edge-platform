################################################################################
# Terraform Version & Provider Constraints
#
# This file locks down the exact versions of Terraform and providers used.
# - Terraform >= 1.5.0: Ensures features like `import` blocks and `check`
#   blocks are available for production workflows.
# - AWS provider ~> 5.0: Latest major version with EKS 1.36 support,
#   default_tags, and full feature coverage for our architecture.
# - Kubernetes provider ~> 2.25: Used to create namespaces, RBAC, network
#   policies, and config maps directly from Terraform.
# - Helm provider ~> 2.12: Deploys platform services (ArgoCD, Istio,
#   Prometheus, Kyverno, Cert-Manager) as Helm charts — all managed by
#   Terraform so a single `terraform destroy` cleans everything up.
# - TLS provider ~> 4.0: Required for OIDC thumbprint calculation which
#   enables IRSA (IAM Roles for Service Accounts) — pods get AWS permissions
#   without static credentials.
#
# The ~> operator (pessimistic constraint) allows patch updates (e.g., 5.0.1)
# but blocks breaking major version changes (e.g., 6.0.0). This prevents
# unexpected drift in production while still receiving bug fixes.
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
