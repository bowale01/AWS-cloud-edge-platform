################################################################################
# Edge Module — Simulated Factory-Floor Edge Site
#
# This module creates a separate VPC with a lightweight k3s Kubernetes
# cluster to simulate an edge site (factory, warehouse, manufacturing plant).
#
# IN THE REAL WORLD:
# - Edge sites are physical hardware at remote locations
# - Connected via VPN, MPLS, or AWS Direct Connect
# - Run lightweight K8s (k3s, MicroK8s) due to resource constraints
# - Must operate independently if cloud connectivity is lost
# - Managed centrally via GitOps (ArgoCD pull-based sync)
#
# WHAT WE SIMULATE:
# - Separate VPC = separate network (like a different physical site)
# - VPC Peering = hybrid connectivity (simulates VPN/Direct Connect)
# - t3.small EC2 = resource-constrained edge hardware
# - k3s = lightweight Kubernetes (~512MB RAM vs ~2GB for full K8s)
# - MQTT broker = industrial IoT protocol (factory sensors/PLCs)
#
# EDGE-TO-CLOUD COMMUNICATION:
# ┌──────────────┐                        ┌──────────────────────┐
# │  Edge Site   │  VPC Peering           │  Cloud Platform      │
# │              │◄──────────────────────►│                      │
# │  k3s Cluster │                        │  EKS Cluster         │
# │  • ArgoCD   ────── pulls config ──────│  • ArgoCD (central)  │
# │    Agent     │                        │                      │
# │  • Fluent   ────── forwards logs ─────│  • CloudWatch        │
# │    Bit       │                        │                      │
# │  • Prom     ────── remote write ──────│  • Prometheus        │
# │    (local)   │                        │    (central)         │
# │  • MQTT     ◄──── IoT devices ────────│                      │
# │    Broker    │                        │                      │
# └──────────────┘                        └──────────────────────┘
################################################################################

#===============================================================================
# Edge VPC
# Completely isolated network — simulates a factory-floor LAN.
# Different CIDR range (172.16.0.0/16) ensures no overlap with platform VPC
# (required for VPC peering to work).
#===============================================================================

resource "aws_vpc" "edge" {
  cidr_block           = var.edge_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-edge-vpc-${var.environment}"
  }
}

#===============================================================================
# Edge Internet Gateway + Public Subnet
# Edge node needs internet for:
# - Pulling container images from ECR
# - Downloading k3s binary during bootstrap
# - ArgoCD agent pulling configs from GitHub
# In production, this would go through a proxy or the VPN to cloud.
#===============================================================================

resource "aws_internet_gateway" "edge" {
  vpc_id = aws_vpc.edge.id

  tags = {
    Name = "${var.project_name}-edge-igw-${var.environment}"
  }
}

resource "aws_subnet" "edge" {
  vpc_id                  = aws_vpc.edge.id
  cidr_block              = cidrsubnet(var.edge_vpc_cidr, 8, 1)  # 172.16.1.0/24
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-edge-subnet-${var.environment}"
  }
}

resource "aws_route_table" "edge" {
  vpc_id = aws_vpc.edge.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.edge.id
  }

  # Route to platform VPC via peering
  route {
    cidr_block                = var.platform_vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.edge_to_platform.id
  }

  tags = {
    Name = "${var.project_name}-edge-rt-${var.environment}"
  }
}

resource "aws_route_table_association" "edge" {
  subnet_id      = aws_subnet.edge.id
  route_table_id = aws_route_table.edge.id
}

#===============================================================================
# VPC Peering — Connects Edge VPC to Platform VPC
# Simulates a VPN or Direct Connect link between factory and cloud.
# VPC peering is free for same-region, low-latency, and encrypted in transit.
#
# In production at scale, you'd use:
# - AWS Site-to-Site VPN ($0.05/hr per connection)
# - AWS Transit Gateway (hub-and-spoke for many edge sites)
# - AWS Direct Connect (dedicated physical link for high bandwidth)
#===============================================================================

resource "aws_vpc_peering_connection" "edge_to_platform" {
  vpc_id      = aws_vpc.edge.id          # Requester (edge)
  peer_vpc_id = var.platform_vpc_id       # Accepter (platform)
  auto_accept = true                      # Same account, same region = auto-accept

  tags = {
    Name = "${var.project_name}-peering-edge-to-platform-${var.environment}"
  }
}

#===============================================================================
# Edge Security Group
# Controls access to the k3s node:
# Edge Security Group
# Controls access to the k3s node:
# - NO SSH (port 22) — access via SSM Session Manager instead (more secure)
# - K3s API (port 6443) from platform VPC (ArgoCD managing the cluster)
# - MQTT (port 1883) from edge subnet (IoT devices)
# - All traffic from platform VPC (monitoring, log collection)
#
# WHY SSM INSTEAD OF SSH?
# - No SSH keys to manage, rotate, or lose
# - No port 22 open (smaller attack surface)
# - Full audit trail in CloudTrail (who accessed what, when)
# - Works through NAT/firewalls (uses HTTPS outbound only)
# - IAM-based access control (not key-based)
#===============================================================================

resource "aws_security_group" "edge_node" {
  name_prefix = "${var.project_name}-edge-node-sg-"
  vpc_id      = aws_vpc.edge.id
  description = "Security group for edge k3s node"

  # NO SSH — use SSM Session Manager: aws ssm start-session --target <instance-id>

  # K3s API server — platform VPC needs access to manage the cluster
  ingress {
    description = "K3s API from platform VPC"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.platform_vpc_cidr]
  }

  # MQTT broker — IoT devices connect here
  ingress {
    description = "MQTT broker"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = [var.edge_vpc_cidr]
  }

  # All traffic from platform VPC (Prometheus scraping, log forwarding)
  ingress {
    description = "All traffic from platform VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.platform_vpc_cidr]
  }

  # Outbound — node needs to pull images, sync with GitHub, forward logs
  # Also required for SSM agent to communicate with AWS SSM service
  egress {
    description = "Allow all outbound (includes SSM agent HTTPS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-edge-node-sg-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

#===============================================================================
# IAM Instance Profile for SSM
# SSM Session Manager requires the AmazonSSMManagedInstanceCore policy.
# This is already attached to EKS nodes — we add it to the edge node too.
# With this, you connect via: aws ssm start-session --target <instance-id>
#===============================================================================

resource "aws_iam_role" "edge_node" {
  name = "${var.project_name}-edge-node-role-${var.environment}"

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
    Name = "${var.project_name}-edge-node-role-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "edge_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.edge_node.name
}

# Also allow pulling images from ECR
resource "aws_iam_role_policy_attachment" "edge_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.edge_node.name
}

resource "aws_iam_instance_profile" "edge_node" {
  name = "${var.project_name}-edge-node-profile-${var.environment}"
  role = aws_iam_role.edge_node.name
}

#===============================================================================
# Edge EC2 Instance — k3s Node
# This single instance runs the entire edge Kubernetes cluster.
# k3s is installed via user_data (cloud-init script on first boot).
#
# What the bootstrap script does:
# 1. Installs k3s (single-node cluster, server + agent)
# 2. Installs Helm (for deploying edge services)
# 3. Creates namespaces for edge workloads
# 4. Outputs kubeconfig to /etc/rancher/k3s/k3s.yaml
#===============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical (official Ubuntu AMIs)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "edge_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.edge.id
  vpc_security_group_ids = [aws_security_group.edge_node.id]
  iam_instance_profile   = aws_iam_instance_profile.edge_node.name

  # No key_name — access via SSM Session Manager only

  # k3s bootstrap script
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Update system
    apt-get update && apt-get upgrade -y

    # Install k3s (lightweight Kubernetes)
    # --disable=traefik: we'll use our own ingress controller
    # --write-kubeconfig-mode=644: make kubeconfig readable
    curl -sfL https://get.k3s.io | sh -s - server \
      --disable=traefik \
      --write-kubeconfig-mode=644 \
      --tls-san=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

    # Wait for k3s to be ready
    until kubectl get nodes --kubeconfig /etc/rancher/k3s/k3s.yaml 2>/dev/null | grep -q "Ready"; do
      sleep 5
    done

    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Create namespaces for edge workloads
    kubectl create namespace edge-services --kubeconfig /etc/rancher/k3s/k3s.yaml
    kubectl create namespace monitoring --kubeconfig /etc/rancher/k3s/k3s.yaml
    kubectl create namespace argocd --kubeconfig /etc/rancher/k3s/k3s.yaml

    # Label the node for scheduling
    kubectl label node $(hostname) \
      role=edge \
      site=factory-floor \
      environment=prod \
      --kubeconfig /etc/rancher/k3s/k3s.yaml

    echo "k3s edge cluster bootstrap complete" > /var/log/rockauto-bootstrap.log
  EOF

  root_block_device {
    volume_size = 30    # 30GB for OS, images, and persistent volumes
    volume_type = "gp3" # Latest generation, better performance than gp2
    encrypted   = true  # Encrypt the root volume at rest
  }

  tags = {
    Name = "${var.project_name}-edge-node-${var.environment}"
    Role = "edge-k3s"
  }
}
