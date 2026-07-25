################################################################################
# Observability Module — Outputs
################################################################################

output "application_log_group_name" {
  description = "CloudWatch log group for application container logs"
  value       = aws_cloudwatch_log_group.application.name
}

output "platform_log_group_name" {
  description = "CloudWatch log group for platform service logs"
  value       = aws_cloudwatch_log_group.platform_services.name
}

output "edge_log_group_name" {
  description = "CloudWatch log group for edge cluster logs"
  value       = aws_cloudwatch_log_group.edge.name
}

output "fluent_bit_policy_arn" {
  description = "IAM policy ARN for Fluent Bit — attach to Fluent Bit's IRSA role"
  value       = aws_iam_policy.fluent_bit.arn
}

output "prometheus_policy_arn" {
  description = "IAM policy ARN for Prometheus CloudWatch integration"
  value       = aws_iam_policy.prometheus.arn
}
