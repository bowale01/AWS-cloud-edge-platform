################################################################################
# VPC Module — Input Variables
################################################################################

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, staging)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to deploy subnets into"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name — needed for subnet tagging so the AWS Load Balancer Controller can discover which subnets to use"
  type        = string
}

variable "edge_vpc_cidr" {
  description = "CIDR of edge VPC for peering route (empty string to skip)"
  type        = string
  default     = ""
}

variable "vpc_peering_connection_id" {
  description = "VPC peering connection ID for routing traffic to edge VPC"
  type        = string
  default     = ""
}
