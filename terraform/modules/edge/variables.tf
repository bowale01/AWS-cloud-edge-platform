################################################################################
# Edge Module — Input Variables
################################################################################

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, staging)"
  type        = string
}

variable "edge_vpc_cidr" {
  description = "CIDR block for the edge VPC (must not overlap with platform VPC)"
  type        = string
}

variable "platform_vpc_id" {
  description = "VPC ID of the platform VPC (for peering connection)"
  type        = string
}

variable "platform_vpc_cidr" {
  description = "CIDR block of the platform VPC (for security group rules and routing)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the edge k3s node"
  type        = string
}

variable "availability_zone" {
  description = "AZ for the edge instance (single AZ — edge sites are typically single-location)"
  type        = string
}
