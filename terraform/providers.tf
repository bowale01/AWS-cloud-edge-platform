################################################################################
# Provider Configuration
#
# This file tells Terraform HOW to authenticate and connect to each service.
#
# AWS Provider:
# - Uses the region defined in variables (us-east-1).
# - `default_tags` automatically applies Project, Environment, and ManagedBy
#   tags to EVERY resource created. This is critical for:
#   • Cost tracking: Filter AWS billing by "rockauto" project tag
#   • Ownership: Know which team/project owns a resource
#   • Automation: Scripts can target resources by tag for cleanup
#   • Compliance: Auditors can verify all infra is tagged and tracked
#
# Kubernetes Provider:
# - Connects to the EKS cluster AFTER it's created.
# - Uses the cluster endpoint, CA cert, and a short-lived auth token.
# - The token comes from `aws_eks_cluster_auth` which generates a temporary
#   credential using your AWS IAM identity — no static kubeconfig needed.
#
# Helm Provider:
# - Same connection as Kubernetes provider.
# - Used to install Helm charts (ArgoCD, Prometheus, Istio, etc.) directly
#   from Terraform — keeping everything in one state file for clean destroy.
#
# Why not just use kubectl/helm CLI?
# - Terraform tracks state: it knows what's deployed and can diff/destroy.
# - Single workflow: `terraform apply` builds infra AND installs platform services.
# - Reproducible: Anyone can run the same code and get the same result.
################################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "rockauto"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# These providers depend on the EKS cluster existing.
# On first run, Terraform will create the cluster first (via the AWS provider),
# then use these providers to deploy Kubernetes resources into it.

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.rockauto.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.rockauto.token
  }
}

# This data source generates a short-lived token to authenticate to EKS.
# It uses your current AWS credentials (CLI profile, env vars, or instance role)
# and exchanges them for a Kubernetes-compatible bearer token.
# Token is valid for ~15 minutes and auto-refreshes on each Terraform run.

data "aws_eks_cluster_auth" "rockauto" {
  name = module.eks.cluster_name
}
