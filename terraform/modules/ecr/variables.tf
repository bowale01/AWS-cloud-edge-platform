################################################################################
# ECR Module — Input Variables
################################################################################

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, staging)"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create. Each becomes rockauto/<name>."
  type        = list(string)
  default = [
    "demo-app",        # Platform demo application
    "edge-worker",     # Edge workload deployed to k3s
    "mqtt-processor"   # MQTT message processor for edge IoT data
  ]
}
