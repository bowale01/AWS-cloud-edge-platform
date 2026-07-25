################################################################################
# EKS Module — Kubernetes Cluster, Node Groups, IRSA, Add-ons
#
# This is the core of the platform. It creates:
# 1. EKS Cluster (managed control plane — API server, etcd, scheduler)
# 2. Managed Node Group (EC2 worker nodes that run pods)
# 3. OIDC Provider (enables IRSA — IAM Roles for Service Accounts)
# 4. EKS Add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI driver)
# 5. IAM roles with least-privilege policies
#
# HOW EKS WORKS:
# ┌─────────────────────────────────────────────────────────────┐
# │  AWS-Managed Control Plane                                   │
# │  ┌──────────┐ ┌──────────┐ ┌────────────┐ ┌─────────────┐  │
# │  │API Server│ │  etcd    │ │ Scheduler  │ │ Controller  │  │
# │  │          │ │(encrypted│ │            │ │ Manager     │  │
# │  │          │ │ with KMS)│ │            │ │             │  │
# │  └──────────┘ └──────────┘ └────────────┘ └─────────────┘  │
# │  (Managed by AWS — HA across 3 AZs, patched automatically)  │
# └──────────────────────────────┬──────────────────────────────┘
#                                │ kubelet API
#                                ▼
# ┌─────────────────────────────────────────────────────────────┐
# │  Customer-Managed Worker Nodes (in private subnets)          │
# │  ┌──────────────────┐  ┌──────────────────┐                 │
# │  │ Node (AZ-a)      │  │ Node (AZ-b)      │                 │
# │  │ • kubelet        │  │ • kubelet        │                 │
# │  │ • kube-proxy     │  │ • kube-proxy     │                 │
# │  │ • VPC CNI        │  │ • VPC CNI        │                 │
# │  │ • Pods...        │  │ • Pods...        │                 │
# │  └──────────────────┘  └──────────────────┘                 │
# └─────────────────────────────────────────────────────────────┘
#
# IRSA (IAM Roles for Service Accounts):
# The OIDC provider allows Kubernetes service accounts to assume IAM roles.
# This means pods get AWS credentials WITHOUT access keys — they use
# short-lived tokens federated through the OIDC trust relationship.
# Example: External Secrets Operator pod → assumes IAM role → reads Secrets Manager
################################################################################

#===============================================================================
# EKS Cluster IAM Role
# The control plane needs an IAM role to manage AWS resources on your behalf
# (create ENIs, manage security groups, write logs, etc.)
#===============================================================================

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role-${var.environment}"

  # Trust policy: only the EKS service can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eks-cluster-role-${var.environment}"
  }
}

# AWS-managed policies that EKS requires
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

#===============================================================================
# EKS Cluster
#===============================================================================

resource "aws_eks_cluster" "rockauto" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  vpc_config {
    # Cluster spans both public and private subnets
    # Worker nodes use private, EKS places ENIs in both for communication
    subnet_ids = concat(var.public_subnet_ids, var.private_subnet_ids)

    # Private endpoint: worker nodes talk to API server over private network
    endpoint_private_access = true

    # Public endpoint: you can run kubectl from your laptop
    # In a locked-down production, you'd set this to false and use a bastion/VPN
    endpoint_public_access = true

    security_group_ids = [aws_security_group.eks_cluster.id]
  }

  # Encrypt Kubernetes Secrets at rest in etcd using our KMS key
  # Without this, secrets are stored base64-encoded (NOT encrypted) in etcd
  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  # Send control plane logs to CloudWatch for audit and debugging
  # These log types cover all aspects of the control plane:
  # - api: all API server requests (who did what)
  # - audit: security audit trail (who accessed what resources)
  # - authenticator: IAM authentication events
  # - controllerManager: controller loop decisions
  # - scheduler: pod scheduling decisions
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Name = var.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

#===============================================================================
# Cluster Security Group
# Controls what network traffic can reach the EKS API server.
# Workers communicate with the control plane over port 443 (HTTPS).
#===============================================================================

resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.project_name}-eks-cluster-sg-"
  vpc_id      = var.vpc_id
  description = "Security group for EKS cluster control plane communication"

  # Allow workers and pods within the VPC to reach the API server
  ingress {
    description = "Allow VPC traffic to cluster API (workers, pods)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound (control plane needs to reach workers, ECR, etc.)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

#===============================================================================
# Node Group IAM Role
# Worker nodes need permissions to:
# - Pull container images from ECR
# - Register themselves with the EKS cluster
# - Manage ENIs for pod networking (VPC CNI)
# - Send logs to CloudWatch
# - Be managed via SSM (for debugging without SSH keys)
#===============================================================================

resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-nodes-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eks-nodes-role-${var.environment}"
  }
}

# Required policies for EKS worker nodes
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# SSM allows you to connect to nodes without SSH keys (more secure)
resource "aws_iam_role_policy_attachment" "eks_ssm_managed" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_nodes.name
}

#===============================================================================
# Managed Node Group
# AWS manages the underlying EC2 instances — handles AMI updates, draining,
# and replacement during upgrades. You define the scaling parameters.
#
# ON_DEMAND instances for production stability (no interruptions).
# Nodes are placed in private subnets (no public IP, no direct internet).
#===============================================================================

resource "aws_eks_node_group" "rockauto_workers" {
  cluster_name    = aws_eks_cluster.rockauto.name
  node_group_name = "${var.project_name}-workers-${var.environment}"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids
  version         = var.cluster_version

  # ON_DEMAND for production — no 2-minute termination risk
  capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # During upgrades, only take down 1 node at a time
  # This ensures workloads stay available (respects PodDisruptionBudgets)
  update_config {
    max_unavailable = 1
  }

  # Labels applied to all nodes — used for scheduling decisions
  labels = {
    role        = "worker"
    environment = var.environment
    project     = var.project_name
  }

  tags = {
    Name = "${var.project_name}-workers-${var.environment}"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry,
  ]
}

#===============================================================================
# EKS Add-ons
# Managed add-ons are AWS-maintained versions of critical cluster components.
# AWS handles updates and compatibility — you just specify the cluster.
#
# - vpc-cni: Assigns VPC IP addresses directly to pods (no overlay network)
# - coredns: Cluster DNS for service discovery
# - kube-proxy: Network rules for Service → Pod routing
# - ebs-csi: Allows pods to use EBS volumes for persistent storage
#===============================================================================

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.rockauto.name
  addon_name   = "vpc-cni"

  # OVERWRITE: if the addon already exists (from cluster creation), update it
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.project_name}-addon-vpc-cni-${var.environment}"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.rockauto.name
  addon_name   = "coredns"

  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.project_name}-addon-coredns-${var.environment}"
  }

  # CoreDNS needs at least one node running to schedule on
  depends_on = [aws_eks_node_group.rockauto_workers]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.rockauto.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.project_name}-addon-kube-proxy-${var.environment}"
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.rockauto.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn  # IRSA role for EBS access

  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.project_name}-addon-ebs-csi-${var.environment}"
  }

  depends_on = [aws_eks_node_group.rockauto_workers]
}

#===============================================================================
# OIDC Provider — Enables IRSA (IAM Roles for Service Accounts)
#
# This is the bridge between Kubernetes identity and AWS IAM.
# Without IRSA, pods would need static AWS access keys (bad practice).
#
# How IRSA works:
# 1. EKS cluster has an OIDC issuer URL (identity provider)
# 2. We register this URL as an IAM OIDC provider in AWS
# 3. IAM roles can now trust tokens issued by this provider
# 4. When a pod uses a service account annotated with a role ARN,
#    the EKS pod identity webhook injects a projected token
# 5. AWS STS validates the token against the OIDC provider
# 6. Pod gets short-lived AWS credentials (no access keys!)
#
# This is ZERO-TRUST identity — every pod gets only the permissions it needs,
# verified cryptographically on every API call.
#===============================================================================

data "tls_certificate" "eks" {
  url = aws_eks_cluster.rockauto.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.rockauto.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-eks-oidc-${var.environment}"
  }
}

#===============================================================================
# EBS CSI Driver IRSA Role
# The EBS CSI driver needs IAM permissions to create/attach/delete EBS volumes.
# Instead of giving the entire node this permission, we scope it to just
# the ebs-csi-controller pod via IRSA.
#===============================================================================

resource "aws_iam_role" "ebs_csi" {
  name = "${var.project_name}-ebs-csi-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.rockauto.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(aws_eks_cluster.rockauto.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ebs-csi-role-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}
