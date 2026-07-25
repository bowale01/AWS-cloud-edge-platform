################################################################################
# Main — Root Module Orchestration
#
# This is the "wiring" file. It calls each child module and passes data
# between them. Think of it as the main() function of the infrastructure.
#
# Module dependency chain:
#   VPC → EKS (needs subnets) → Platform Services (needs cluster)
#   Security (KMS) → EKS (needs encryption key)
#   ECR → CI/CD (needs registry for image push)
#   Edge VPC → VPC Peering → Route Tables (needs both VPCs)
#
# All resources follow the naming convention: rockauto-<component>-prod
################################################################################

#===============================================================================
# Data Sources
#===============================================================================

# Get current AWS account ID and region for use in IAM policies and ARNs
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#===============================================================================
# Local Values
# Computed values reused across modules. Keeps the code DRY.
#===============================================================================

locals {
  cluster_name = "${var.project_name}-eks-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

#===============================================================================
# Module: VPC (Platform)
# Creates the network foundation — VPC, subnets, NAT, route tables.
# EKS worker nodes run in private subnets (no direct internet exposure).
# ALB sits in public subnets (receives external traffic).
#===============================================================================

module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  cluster_name       = local.cluster_name

  # Peering routes are added after the edge VPC and peering are created
  edge_vpc_cidr             = var.edge_vpc_cidr
  vpc_peering_connection_id = module.edge.vpc_peering_connection_id
}

#===============================================================================
# Module: Security (KMS + Secrets Manager)
# Creates encryption keys and secret storage BEFORE EKS — because the
# cluster needs the KMS key ARN at creation time to encrypt etcd secrets.
#===============================================================================

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  account_id   = data.aws_caller_identity.current.account_id
}

#===============================================================================
# Module: EKS Cluster
# Creates the Kubernetes control plane, managed node group, OIDC provider
# (for IRSA), and EKS add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI).
# Nodes are ON_DEMAND (not spot) — this is production.
#===============================================================================

module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  cluster_name        = local.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = var.vpc_cidr
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  use_spot_instances  = var.use_spot_instances
  kms_key_arn         = module.security.kms_key_arn
}

#===============================================================================
# Module: ECR (Container Registry)
# Private Docker registry for storing application and platform images.
# Images are scanned for vulnerabilities on push (scan_on_push = true).
# Lifecycle policy removes untagged images after 7 days to control cost.
#===============================================================================

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

#===============================================================================
# Module: Edge (Simulated Edge Site)
# Creates a separate VPC with a k3s node to simulate a factory-floor
# edge cluster. Connected to the platform VPC via VPC peering.
# In a real environment, this would be physical hardware connected via
# VPN or AWS Direct Connect.
#===============================================================================

module "edge" {
  source = "./modules/edge"

  project_name      = var.project_name
  environment       = var.environment
  edge_vpc_cidr     = var.edge_vpc_cidr
  platform_vpc_id   = module.vpc.vpc_id
  platform_vpc_cidr = var.vpc_cidr
  instance_type     = var.edge_instance_type
  availability_zone = var.availability_zones[0]
}

#===============================================================================
# Module: Observability (CloudWatch Log Groups)
# Pre-creates log groups with retention policies so we control naming,
# encryption, and cost (logs are expensive if retained forever).
#===============================================================================

module "observability" {
  source = "./modules/observability"

  project_name = var.project_name
  environment  = var.environment
  cluster_name = local.cluster_name
  kms_key_arn  = module.security.kms_key_arn
}
