################################################################################
# Variables — Configurable Inputs for the RockAuto Platform
#
# Variables make the infrastructure reusable and environment-aware.
# Instead of hardcoding values, we parameterize them so:
# - The same code can deploy to different environments (prod, staging)
# - Instance sizes can be adjusted without changing logic
# - Teams can override defaults via tfvars files or CLI flags
#
# Usage:
#   terraform apply -var="environment=prod" -var="aws_region=us-east-1"
#   OR
#   terraform apply -var-file="environments/prod/terraform.tfvars"
################################################################################

#===============================================================================
# General
#===============================================================================

variable "aws_region" {
  description = "AWS region for all resources. us-east-1 chosen for widest service availability and lowest cost."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name used in resource naming and tagging (e.g., prod, staging)."
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name prefix for all resources. Ensures every resource is identifiable in the AWS console and billing."
  type        = string
  default     = "rockauto"
}

#===============================================================================
# Networking — VPC
# The VPC is the network foundation. We use a /16 CIDR which gives us 65,536
# IP addresses — enough to carve out public, private, and isolated subnets
# across multiple AZs without running out of IPs.
#===============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC. /16 gives us room for ~256 subnets of /24 each."
  type        = string
  default     = "10.0.0.0/16"
}

variable "edge_vpc_cidr" {
  description = "CIDR block for the edge VPC. Must NOT overlap with platform VPC (required for VPC peering)."
  type        = string
  default     = "172.16.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy into. Two AZs gives us high availability without tripling the NAT Gateway cost."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

#===============================================================================
# EKS Cluster
# EKS is the managed Kubernetes service. AWS handles the control plane
# (API server, etcd, scheduler) — we manage the worker nodes.
#===============================================================================

variable "cluster_version" {
  description = "Kubernetes version for EKS. Pin to a specific minor version to control upgrades."
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for worker nodes. t3.medium = 2 vCPU, 4GB RAM — good for platform services."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes. 2 nodes = high availability across AZs."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum nodes (autoscaler won't go below this). 1 = allows scale-down to save cost."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum nodes (autoscaler ceiling). 3 = handles burst without runaway costs."
  type        = number
  default     = 3
}

variable "use_spot_instances" {
  description = "Use EC2 Spot instances for workers. Disabled for production — spot instances can be interrupted with 2-minute notice which is unacceptable for production workloads."
  type        = bool
  default     = false
}

#===============================================================================
# Edge Simulation
# The edge site simulates a factory-floor Kubernetes cluster running k3s.
# In production, this would be physical hardware at a manufacturing plant.
# Here we simulate it with a small EC2 instance in a separate VPC.
#===============================================================================

variable "edge_instance_type" {
  description = "EC2 instance type for edge k3s node. t3.small = 2 vCPU, 2GB RAM — mimics constrained edge hardware."
  type        = string
  default     = "t3.small"
}
