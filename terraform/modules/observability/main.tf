################################################################################
# Observability Module — CloudWatch Log Groups + IAM for Fluent Bit
#
# This module pre-creates the logging infrastructure that Fluent Bit
# (running as a DaemonSet on every node) will ship container logs into.
#
# WHY PRE-CREATE LOG GROUPS?
# - Control naming convention (rockauto-* prefix)
# - Set retention policies (logs are EXPENSIVE if kept forever)
# - Apply KMS encryption (logs may contain sensitive data)
# - Prevent Fluent Bit from auto-creating groups with wrong settings
#
# OBSERVABILITY STACK OVERVIEW:
# ┌─────────────────────────────────────────────────────────────────┐
# │  METRICS (What's happening right now?)                          │
# │  Prometheus ──► scrapes /metrics ──► Grafana dashboards         │
# │  • Request rate, error rate, latency (RED method)               │
# │  • CPU, memory, disk utilization per pod/node                   │
# │  • Custom business metrics                                      │
# ├─────────────────────────────────────────────────────────────────┤
# │  LOGS (What happened and why?)                                  │
# │  Pods (stdout) ──► Fluent Bit DaemonSet ──► CloudWatch Logs     │
# │  • Application logs (structured JSON)                           │
# │  • EKS control plane logs (audit, API, authenticator)           │
# │  • Edge cluster logs (forwarded via Fluent Bit)                 │
# ├─────────────────────────────────────────────────────────────────┤
# │  TRACES (How did the request flow between services?)            │
# │  Istio sidecar ──► Jaeger/Tempo ──► Grafana                    │
# │  • Distributed traces across microservices                      │
# │  • Latency breakdown per service hop                            │
# └─────────────────────────────────────────────────────────────────┘
#
# COST CONTROL:
# CloudWatch Logs charges per GB ingested ($0.50/GB) and stored ($0.03/GB/month).
# Retention policies prevent indefinite growth. For this platform:
# - Application logs: 30 days (recent debugging)
# - Platform logs: 90 days (incident investigation)
# - EKS control plane: 30 days (handled by EKS itself)
################################################################################

#===============================================================================
# Log Groups — Application Logs
# Fluent Bit ships container logs here, organized by namespace.
# Each namespace gets its own log group for access control and cost tracking.
#===============================================================================

resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${var.cluster_name}/application"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-logs-application-${var.environment}"
  }
}

resource "aws_cloudwatch_log_group" "platform_services" {
  name              = "/aws/eks/${var.cluster_name}/platform"
  retention_in_days = 90  # Keep longer — needed for incident investigation
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-logs-platform-${var.environment}"
  }
}

resource "aws_cloudwatch_log_group" "edge" {
  name              = "/aws/eks/${var.cluster_name}/edge"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-logs-edge-${var.environment}"
  }
}

#===============================================================================
# IAM Policy for Fluent Bit (IRSA)
# Fluent Bit pods need permission to write logs to CloudWatch.
# This policy is attached to the Fluent Bit service account via IRSA.
# Scoped to only our log groups — cannot write to other accounts' logs.
#===============================================================================

resource "aws_iam_policy" "fluent_bit" {
  name        = "${var.project_name}-fluent-bit-policy-${var.environment}"
  description = "Allows Fluent Bit to write logs to CloudWatch log groups"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLogCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.application.arn}:*",
          "${aws_cloudwatch_log_group.platform_services.arn}:*",
          "${aws_cloudwatch_log_group.edge.arn}:*"
        ]
      },
      {
        Sid    = "AllowKMSEncryption"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = [var.kms_key_arn]
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-fluent-bit-policy-${var.environment}"
  }
}

#===============================================================================
# IAM Policy for CloudWatch Agent / Prometheus Remote Write (IRSA)
# If using Amazon Managed Prometheus or CloudWatch Container Insights,
# pods need permission to write metrics.
#===============================================================================

resource "aws_iam_policy" "prometheus" {
  name        = "${var.project_name}-prometheus-policy-${var.environment}"
  description = "Allows Prometheus to write metrics to CloudWatch (if using Container Insights)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMetricsWrite"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "${var.project_name}/${var.environment}"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-prometheus-policy-${var.environment}"
  }
}
