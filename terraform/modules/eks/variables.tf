################################################################################
# EKS Module — Input Variables
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
  description = "Name of the EKS cluster (e.g., rockauto-eks-prod)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for EKS (e.g., 1.29)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — used in security group rules"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (used for EKS API endpoint if public access enabled)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where worker nodes are deployed"
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}

variable "use_spot_instances" {
  description = "Whether to use spot instances (false for production)"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting Kubernetes secrets in etcd"
  type        = string
}
