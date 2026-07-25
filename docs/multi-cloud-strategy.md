# RockAuto - Multi-Cloud Strategy

## Overview

This document outlines the multi-cloud readiness strategy for the RockAuto platform. While the current implementation targets AWS, the architecture is designed with portability in mind to support future expansion to Azure (primary) and GCP (secondary).

---

## Current State: AWS Foundation

| Layer | AWS Service | Purpose |
|-------|-------------|---------|
| Kubernetes | EKS | Central cloud workload runtime |
| Edge Kubernetes | k3s on EC2 | Lightweight edge runtime |
| Networking | VPC, ALB, VPN | Connectivity & ingress |
| Identity | IAM, IRSA | Workload identity |
| Secrets | Secrets Manager | Secret storage |
| Observability | CloudWatch | Centralized logging |
| Container Registry | ECR | Image storage |
| Encryption | KMS | Data encryption at rest |
| IaC | Terraform | Infrastructure provisioning |

---

## Target State: Azure Expansion (Priority)

### Why Azure First
- Rockwell Automation's enterprise ecosystem aligns with Microsoft Azure
- Azure Arc provides native hybrid/edge fleet management
- Azure IoT Hub integrates natively with industrial protocols (OPC-UA, MQTT)
- AKS offers tight integration with Azure AD for enterprise identity

### Azure Equivalent Mapping

| Layer | AWS (Current) | Azure (Target) | Migration Complexity |
|-------|---------------|----------------|---------------------|
| Kubernetes | EKS | AKS | Medium - different node pool config |
| Edge Management | k3s + ArgoCD | Azure Arc-enabled K8s | Low - Arc agents on existing k3s |
| Networking | VPC + VPN | VNet + ExpressRoute/VPN | Medium - re-provision networking |
| Identity | IRSA | Azure Workload Identity | Medium - different federation model |
| Secrets | Secrets Manager | Azure Key Vault | Low - ESO supports both backends |
| Observability | CloudWatch | Azure Monitor + Log Analytics | Medium - different query language |
| Container Registry | ECR | ACR | Low - standard OCI registries |
| Encryption | KMS | Azure Key Vault (CMK) | Low - envelope encryption pattern |
| IaC | Terraform | Terraform (or Bicep) | Low - new provider, same patterns |
| GitOps | ArgoCD | ArgoCD (or Azure Flux) | Low - ArgoCD is cloud-agnostic |
| Policy | Kyverno | Kyverno + Azure Policy | Low - Kyverno works on any K8s |
| Service Mesh | Istio | Istio (or Azure Service Mesh) | Low - Istio is cloud-agnostic |

---

## Portability Principles

### 1. Cloud-Agnostic Application Layer
- All workloads are containerized and deployed via Kubernetes manifests
- No cloud-specific APIs in application code
- Use Kubernetes-native abstractions (Services, Ingress, ConfigMaps) over cloud-specific equivalents

### 2. Abstraction Through Operators
- **External Secrets Operator**: Abstracts secret backends (AWS SM, Azure KV, GCP SM)
- **Cert-Manager**: Works across clouds with different issuers
- **External DNS**: Manages DNS records across Route53, Azure DNS, Cloud DNS
- **Crossplane** (future): Cloud resource provisioning from Kubernetes

### 3. GitOps as the Deployment Standard
- ArgoCD is cloud-agnostic — runs on any conformant Kubernetes cluster
- Git repository is the single source of truth regardless of cloud target
- Cluster registration is the only cloud-specific operation

### 4. Terraform Module Abstraction
```
terraform/
├── modules/
│   ├── kubernetes/          # Cloud-specific K8s provisioning
│   │   ├── aws/            # EKS module
│   │   ├── azure/          # AKS module (future)
│   │   └── gcp/            # GKE module (future)
│   ├── networking/          # Cloud-specific networking
│   │   ├── aws/            # VPC module
│   │   ├── azure/          # VNet module (future)
│   │   └── gcp/            # VPC module (future)
│   └── platform/           # Cloud-agnostic Helm deployments
│       ├── argocd/
│       ├── istio/
│       └── observability/
```

### 5. Observability Abstraction
- Prometheus is the universal metrics standard (runs anywhere)
- Grafana dashboards are cloud-agnostic
- Fluent Bit supports multiple output backends (CloudWatch, Azure Monitor, Loki)
- OpenTelemetry Collector for vendor-neutral tracing (future)

---

## GCP Considerations (Secondary)

| Layer | GCP Equivalent |
|-------|----------------|
| Kubernetes | GKE (Autopilot or Standard) |
| Edge | Anthos for bare metal |
| Networking | VPC + Cloud Interconnect |
| Identity | Workload Identity Federation |
| Secrets | Secret Manager |
| Observability | Cloud Operations Suite |
| Registry | Artifact Registry |

---

## Migration Path: AWS → Azure

### Phase 1: Parallel Infrastructure (Weeks 1-2)
1. Provision AKS cluster using Terraform Azure modules
2. Set up Azure VNet with VPN/peering to edge sites
3. Deploy ArgoCD on AKS (same Git repo, new cluster target)
4. Configure External Secrets Operator with Azure Key Vault backend

### Phase 2: Workload Migration (Weeks 3-4)
1. Replicate container images to ACR
2. Register AKS cluster in ArgoCD
3. Deploy platform services (Istio, Prometheus, Kyverno)
4. Migrate edge sites from AWS VPN to Azure VPN (or Azure Arc enrollment)

### Phase 3: Validation & Cutover (Week 5)
1. Run workloads in parallel across both clouds
2. Validate observability, security policies, and networking
3. Shift traffic via DNS weighted routing
4. Decommission AWS resources (or retain as DR)

---

## Multi-Cloud Governance

### Consistent Policies Across Clouds
- Kyverno policies are cluster-level (cloud-agnostic)
- Network policies follow the same default-deny model
- RBAC templates are standardized per team/namespace
- Image signing and admission policies apply universally

### Centralized Observability
- Thanos or Grafana Mimir for multi-cluster Prometheus federation
- Grafana as a single pane of glass for all clusters
- Unified alerting rules regardless of cloud provider

### Unified GitOps
- Single ArgoCD instance (or federated instances) managing all clusters
- ApplicationSets for templated multi-cluster deployments
- Progressive delivery with Argo Rollouts across clusters

---

## Key Takeaways

1. **The architecture is designed for portability** — Kubernetes is the abstraction layer
2. **Cloud-specific bits are isolated** in Terraform modules and operator configurations
3. **Azure is the natural next step** given enterprise alignment
4. **Azure Arc** would simplify edge management significantly over the current k3s + ArgoCD approach
5. **No vendor lock-in** at the application or platform layer — only at the infrastructure provisioning layer
