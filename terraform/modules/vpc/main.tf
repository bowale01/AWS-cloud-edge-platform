################################################################################
# VPC Module — Network Foundation for the RockAuto Platform
#
# This module creates the entire network layer:
# - VPC with DNS support (required for EKS)
# - Public subnets (ALB, NAT Gateway)
# - Private subnets (EKS worker nodes — no direct internet access)
# - Internet Gateway (public subnet outbound)
# - NAT Gateway (private subnet outbound — image pulls, API calls)
# - Route tables with proper associations
#
# SUBNET STRATEGY:
# ┌─────────────────────────────────────────────────────────────────┐
# │  Public Subnets (10.0.1.0/24, 10.0.2.0/24)                     │
# │  - ALB (receives external HTTPS traffic)                        │
# │  - NAT Gateway (provides outbound internet for private subnets) │
# │  - map_public_ip_on_launch = true                               │
# ├─────────────────────────────────────────────────────────────────┤
# │  Private Subnets (10.0.10.0/24, 10.0.20.0/24)                  │
# │  - EKS Worker Nodes (no public IPs, protected)                  │
# │  - Outbound traffic goes via NAT Gateway                        │
# │  - Inbound traffic comes only from ALB                          │
# └─────────────────────────────────────────────────────────────────┘
#
# WHY THIS MATTERS:
# - Defense in depth: worker nodes have zero internet exposure
# - ALB handles TLS termination in public subnets
# - NAT Gateway = controlled outbound (can be monitored/restricted)
# - Two AZs = high availability (if one AZ goes down, services survive)
#
# EKS SUBNET TAGS:
# AWS Load Balancer Controller uses these tags to auto-discover subnets:
# - "kubernetes.io/role/elb" = "1"           → public (for internet-facing ALB)
# - "kubernetes.io/role/internal-elb" = "1"  → private (for internal ALB)
# - "kubernetes.io/cluster/<name>" = "shared" → belongs to this cluster
################################################################################

#===============================================================================
# VPC
#===============================================================================

resource "aws_vpc" "platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # Required for EKS — nodes need DNS names
  enable_dns_support   = true  # Required for EKS — enables Route 53 resolver

  tags = {
    Name = "${var.project_name}-platform-vpc-${var.environment}"
  }
}

#===============================================================================
# Internet Gateway
# Allows resources in public subnets to reach the internet directly.
# Without this, the ALB couldn't serve external traffic.
#===============================================================================

resource "aws_internet_gateway" "platform" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "${var.project_name}-igw-${var.environment}"
  }
}

#===============================================================================
# Public Subnets
# One per AZ for high availability. ALB needs at least 2 subnets in
# different AZs to operate.
#===============================================================================

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.platform.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)  # 10.0.1.0/24, 10.0.2.0/24
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true  # Instances here get public IPs automatically

  tags = {
    Name                                        = "${var.project_name}-public-${var.availability_zones[count.index]}-${var.environment}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

#===============================================================================
# Private Subnets
# Worker nodes run here — completely isolated from the internet.
# The only inbound path is through the ALB (via security groups).
#===============================================================================

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.platform.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)  # 10.0.10.0/24, 10.0.20.0/24
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                        = "${var.project_name}-private-${var.availability_zones[count.index]}-${var.environment}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

#===============================================================================
# NAT Gateways (One per AZ — Production HA)
# Each AZ gets its own NAT Gateway so private subnets can reach the internet
# independently. If one AZ goes down, the other AZ still has outbound access.
#
# Cost: ~$32/month per NAT Gateway × 2 = ~$64/month
# This is the production-grade pattern. Single NAT is a dev shortcut.
#===============================================================================

resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${var.availability_zones[count.index]}-${var.environment}"
  }
}

resource "aws_nat_gateway" "platform" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-${var.availability_zones[count.index]}-${var.environment}"
  }

  depends_on = [aws_internet_gateway.platform]
}

#===============================================================================
# Route Tables (One per AZ for private subnets)
#
# Public Route Table:  0.0.0.0/0 → Internet Gateway (shared across AZs)
# Private Route Tables: 0.0.0.0/0 → NAT Gateway in same AZ (HA pattern)
#
# Each private subnet routes through its own AZ's NAT Gateway.
# This ensures AZ isolation — failure in one AZ doesn't affect the other.
#===============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.platform.id
  }

  # Route to edge VPC via peering (added when peering exists)
  dynamic "route" {
    for_each = var.edge_vpc_cidr != "" && var.vpc_peering_connection_id != "" ? [1] : []
    content {
      cidr_block                = var.edge_vpc_cidr
      vpc_peering_connection_id = var.vpc_peering_connection_id
    }
  }

  tags = {
    Name = "${var.project_name}-public-rt-${var.environment}"
  }
}

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.platform[count.index].id
  }

  # Route to edge VPC via peering
  dynamic "route" {
    for_each = var.edge_vpc_cidr != "" && var.vpc_peering_connection_id != "" ? [1] : []
    content {
      cidr_block                = var.edge_vpc_cidr
      vpc_peering_connection_id = var.vpc_peering_connection_id
    }
  }

  tags = {
    Name = "${var.project_name}-private-rt-${var.availability_zones[count.index]}-${var.environment}"
  }
}

#===============================================================================
# Route Table Associations
# Public subnets share one route table (Internet Gateway is AZ-independent).
# Private subnets each get their own route table (routed to their AZ's NAT).
#===============================================================================

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
