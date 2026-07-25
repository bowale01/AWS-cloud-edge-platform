# RockAuto - EKS Cluster Upgrade Runbook

## Overview

This runbook covers the process for upgrading an Amazon EKS cluster from one Kubernetes version to the next. The upgrade follows a specific order to maintain cluster stability:

**Upgrade Order:** Control Plane → Add-ons → Node Groups → Platform Services

---

## Pre-Upgrade Checklist

- [ ] Review [EKS Kubernetes version support](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [ ] Check [EKS release calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html#kubernetes-release-calendar) for deprecation dates
- [ ] Review Kubernetes [changelog](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG) for breaking API changes
- [ ] Run `kubectl get apiservices` — verify no deprecated APIs in use
- [ ] Run `pluto detect-all-in-cluster` — detect deprecated API usage
- [ ] Verify all platform add-on compatibility with target K8s version:
  - ArgoCD
  - Istio
  - Prometheus Operator
  - Kyverno
  - Cert-Manager
  - AWS Load Balancer Controller
  - External Secrets Operator
- [ ] Ensure PodDisruptionBudgets are configured for critical workloads
- [ ] Confirm backup of etcd (EKS manages this, but verify cluster state)
- [ ] Notify teams of maintenance window
- [ ] Ensure monitoring dashboards are accessible

---

## Phase 1: Upgrade Control Plane

The EKS control plane is managed by AWS. This is a non-disruptive operation — existing workloads continue running.

### Via Terraform (Recommended)

```hcl
# terraform/modules/eks/main.tf
resource "aws_eks_cluster" "rockauto" {
  name    = "rockauto-eks-prod"
  version = "1.36"  # Change from current to target version
  # ... rest of config
}
```

```bash
# Plan the upgrade
terraform plan -target=module.eks.aws_eks_cluster.rockauto

# Apply (takes 20-30 minutes)
terraform apply -target=module.eks.aws_eks_cluster.rockauto
```

### Verification
```bash
# Confirm control plane version
kubectl version --short

# Check cluster status
aws eks describe-cluster --name rockauto-eks-prod --query "cluster.status"

# Verify API server is responding
kubectl get nodes
kubectl get pods -A
```

### Expected Duration
- 20-40 minutes
- No workload disruption during control plane upgrade

---

## Phase 2: Upgrade EKS Add-ons

Update managed add-ons to versions compatible with the new control plane.

### Add-ons to Update
1. `vpc-cni` (Amazon VPC CNI)
2. `kube-proxy`
3. `coredns`
4. `aws-ebs-csi-driver`

### Via Terraform

```hcl
# terraform/modules/eks/addons.tf
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.rockauto.name
  addon_name    = "vpc-cni"
  addon_version = "v1.16.0-eksbuild.1"  # Update to compatible version
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.rockauto.name
  addon_name    = "kube-proxy"
  addon_version = "v1.36.0-eksbuild.1"  # Match K8s version
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.rockauto.name
  addon_name    = "coredns"
  addon_version = "v1.11.1-eksbuild.4"  # Update to compatible version
}
```

```bash
# Check available addon versions
aws eks describe-addon-versions --kubernetes-version 1.36 --addon-name vpc-cni

# Apply addon upgrades
terraform apply -target=module.eks.aws_eks_addon.vpc_cni
terraform apply -target=module.eks.aws_eks_addon.kube_proxy
terraform apply -target=module.eks.aws_eks_addon.coredns
```

### Verification
```bash
# Check addon status
aws eks describe-addon --cluster-name rockauto-eks-prod --addon-name vpc-cni
aws eks describe-addon --cluster-name rockauto-eks-prod --addon-name kube-proxy
aws eks describe-addon --cluster-name rockauto-eks-prod --addon-name coredns

# Verify CoreDNS resolution
kubectl run dns-test --image=busybox --restart=Never -- nslookup kubernetes.default
kubectl logs dns-test
kubectl delete pod dns-test
```

---

## Phase 3: Upgrade Node Groups

Node groups must run the same or one minor version below the control plane.

### Strategy: Rolling Update (Zero Downtime)

```hcl
# terraform/modules/eks/node_groups.tf
resource "aws_eks_node_group" "rockauto_workers" {
  cluster_name    = aws_eks_cluster.rockauto.name
  node_group_name = "rockauto-workers-prod"
  version         = "1.36"  # Update to match control plane

  update_config {
    max_unavailable = 1  # Roll one node at a time
  }
}
```

```bash
# Apply node group upgrade (rolling)
terraform apply -target=module.eks.aws_eks_node_group.rockauto_workers
```

### Alternative: Blue-Green Node Group

For zero-risk upgrades, create a new node group then drain the old one:

```bash
# 1. Create new node group (via Terraform with new name)
# 2. Wait for new nodes to be Ready
kubectl get nodes -w

# 3. Cordon old nodes
kubectl cordon <old-node-1>
kubectl cordon <old-node-2>

# 4. Drain old nodes (respects PDBs)
kubectl drain <old-node-1> --ignore-daemonsets --delete-emptydir-data
kubectl drain <old-node-2> --ignore-daemonsets --delete-emptydir-data

# 5. Verify all pods rescheduled
kubectl get pods -A -o wide | grep <old-node>

# 6. Delete old node group via Terraform
```

### Verification
```bash
# All nodes on target version
kubectl get nodes -o wide

# No pods in Pending state
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# Check node conditions
kubectl describe nodes | grep -A5 "Conditions:"
```

### Expected Duration
- 10-15 minutes per node (rolling)
- Pods are gracefully evicted and rescheduled

---

## Phase 4: Upgrade Platform Services

After infrastructure is upgraded, update Helm charts for platform services.

### Update Order (respect dependencies)
1. Istio (CRDs first, then control plane, then data plane)
2. Cert-Manager
3. Kyverno
4. Prometheus Stack
5. ArgoCD
6. External Secrets Operator
7. AWS Load Balancer Controller
8. Fluent Bit

### Istio Upgrade (Canary Method)
```bash
# Install new control plane revision
istioctl install --set revision=1-20 --set profile=default

# Relabel namespaces to use new revision
kubectl label namespace default istio.io/rev=1-20 --overwrite

# Restart workloads to pick up new sidecar
kubectl rollout restart deployment -n <namespace>

# Verify new sidecar version
istioctl proxy-status

# Remove old revision after validation
istioctl uninstall --revision=1-19
```

### Other Services (via ArgoCD)
```bash
# Update Helm chart versions in Git
# ArgoCD will detect drift and sync

# Or force sync
argocd app sync prometheus-stack
argocd app sync kyverno
argocd app sync cert-manager
```

---

## Phase 5: Post-Upgrade Validation

### Functional Tests
```bash
# Verify all pods healthy
kubectl get pods -A | grep -v "Running\|Completed"

# Check ArgoCD sync status
argocd app list

# Verify Istio mTLS
istioctl analyze -A

# Check Kyverno policies
kubectl get cpol -A

# Test ingress
curl -v https://rockauto-demo.example.com/health

# Verify metrics collection
kubectl port-forward svc/prometheus-server 9090:9090 -n monitoring
# Open http://localhost:9090 and run: up{}
```

### Edge Cluster Connectivity
```bash
# Verify VPN tunnel is up
aws ec2 describe-vpn-connections --query "VpnConnections[].VgwTelemetry"

# Check edge cluster registration in ArgoCD
argocd cluster list

# Verify edge workloads
kubectl --context edge-cluster get pods -A
```

---

## Rollback Procedure

### Control Plane
- **EKS does NOT support control plane downgrade**
- If issues arise, focus on fixing forward or rolling back workloads

### Node Groups
```bash
# Revert Terraform version and apply
# terraform/modules/eks/node_groups.tf → version = "1.28"
terraform apply -target=module.eks.aws_eks_node_group.rockauto_workers
```

### Platform Services
```bash
# ArgoCD: revert Git commit and sync
git revert <upgrade-commit>
git push
argocd app sync <app-name>
```

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| Pods stuck in Pending | Insufficient capacity during rolling update | Increase max_unavailable or add temporary capacity |
| API errors after upgrade | Deprecated API usage | Use `kubectl convert` or update manifests |
| CoreDNS not resolving | Addon version mismatch | Verify CoreDNS addon version matches K8s version |
| Nodes NotReady | kubelet version skew | Ensure node AMI matches target version |
| Istio 503 errors | Sidecar version mismatch | Restart pods to inject new sidecar |
| ArgoCD sync failed | CRD schema changes | Update CRDs before application sync |

---

## Communication Template

```
Subject: [RockAuto] EKS Cluster Upgrade - <cluster-name> - <date>

Status: IN PROGRESS / COMPLETE / ROLLED BACK

Cluster: rockauto-eks-prod
From Version: 1.35
To Version: 1.36

Timeline:
- Start: <time>
- Control Plane Complete: <time>
- Node Group Complete: <time>
- Platform Services Complete: <time>
- Validation Complete: <time>

Impact: None expected (rolling upgrade with PDBs)

Contact: <on-call engineer>
```
