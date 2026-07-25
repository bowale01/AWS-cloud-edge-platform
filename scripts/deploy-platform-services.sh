#!/bin/bash
################################################################################
# Deploy Platform Services — Install All Helm Charts in Correct Order
#
# This script installs platform services onto the EKS cluster.
# ORDER MATTERS — some services depend on others:
#
# 1. Cert-Manager (other services need TLS certs)
# 2. Kyverno (policies must be active before apps deploy)
# 3. Istio (service mesh must be ready before injecting sidecars)
# 4. AWS LB Controller (creates ALBs for ingress)
# 5. External Secrets Operator (fetches secrets from AWS)
# 6. Prometheus + Grafana (monitoring stack)
# 7. Fluent Bit (log shipping)
# 8. ArgoCD (GitOps — manages everything after initial install)
#
# USAGE:
#   chmod +x scripts/deploy-platform-services.sh
#   ./scripts/deploy-platform-services.sh
#
# PREREQUISITES:
#   - kubectl configured (make kubeconfig)
#   - Helm 3 installed
#   - Cluster running and nodes Ready
################################################################################

set -euo pipefail

echo "============================================"
echo "  RockAuto Platform Services Deployment"
echo "============================================"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
  echo -e "\n${GREEN}[STEP $1]${NC} $2"
}

print_wait() {
  echo -e "${YELLOW}  Waiting for $1 to be ready...${NC}"
}

#===============================================================================
# Step 0: Create namespaces
#===============================================================================
print_step "0" "Creating namespaces"
kubectl apply -f kubernetes/base/namespaces/namespaces.yaml

#===============================================================================
# Step 1: Cert-Manager
#===============================================================================
print_step "1" "Installing Cert-Manager (TLS certificate automation)"
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --values kubernetes/platform/cert-manager/values.yaml \
  --wait

print_wait "cert-manager"
kubectl rollout status deployment cert-manager -n cert-manager --timeout=120s

#===============================================================================
# Step 2: Kyverno
#===============================================================================
print_step "2" "Installing Kyverno (policy engine)"
helm repo add kyverno https://kyverno.github.io/kyverno/

helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --values kubernetes/platform/kyverno/values.yaml \
  --wait

# Apply our policies
echo "  Applying Kyverno policies..."
kubectl apply -f policies/kyverno/

#===============================================================================
# Step 3: Istio
#===============================================================================
print_step "3" "Installing Istio (service mesh with mTLS)"
helm repo add istio https://istio-release.storage.googleapis.com/charts

# Install Istio base (CRDs)
helm upgrade --install istio-base istio/base \
  --namespace istio-system \
  --create-namespace \
  --wait

# Install Istiod (control plane)
helm upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --values kubernetes/platform/istio/values.yaml \
  --wait

print_wait "istiod"
kubectl rollout status deployment istiod -n istio-system --timeout=120s

# Enable STRICT mTLS mesh-wide
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF

#===============================================================================
# Step 4: AWS Load Balancer Controller
#===============================================================================
print_step "4" "Installing AWS Load Balancer Controller"
helm repo add eks https://aws.github.io/eks-charts

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --values kubernetes/platform/aws-lb-controller/values.yaml \
  --wait

#===============================================================================
# Step 5: External Secrets Operator
#===============================================================================
print_step "5" "Installing External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace rockauto-security \
  --create-namespace \
  --values kubernetes/platform/external-secrets/values.yaml \
  --wait

#===============================================================================
# Step 6: Prometheus + Grafana
#===============================================================================
print_step "6" "Installing Prometheus + Grafana (monitoring)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace rockauto-monitoring \
  --create-namespace \
  --values kubernetes/platform/prometheus-stack/values.yaml \
  --wait

print_wait "prometheus"
kubectl rollout status deployment prometheus-grafana -n rockauto-monitoring --timeout=180s

#===============================================================================
# Step 7: Fluent Bit
#===============================================================================
print_step "7" "Installing Fluent Bit (log shipping to CloudWatch)"
helm repo add fluent https://fluent.github.io/helm-charts

helm upgrade --install fluent-bit fluent/fluent-bit \
  --namespace rockauto-monitoring \
  --values kubernetes/platform/fluent-bit/values.yaml \
  --wait

#===============================================================================
# Step 8: ArgoCD
#===============================================================================
print_step "8" "Installing ArgoCD (GitOps)"
helm repo add argo https://argoproj.github.io/argo-helm

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values kubernetes/platform/argocd/values.yaml \
  --wait

print_wait "argocd"
kubectl rollout status deployment argocd-server -n argocd --timeout=180s

#===============================================================================
# Step 9: Apply base resources (RBAC, Network Policies)
#===============================================================================
print_step "9" "Applying RBAC and Network Policies"
kubectl apply -f kubernetes/base/rbac/rbac.yaml
kubectl apply -f kubernetes/base/network-policies/default-deny.yaml

#===============================================================================
# Summary
#===============================================================================
echo ""
echo "============================================"
echo -e "  ${GREEN}Platform Services Deployed Successfully!${NC}"
echo "============================================"
echo ""
echo "Services installed:"
echo "  ✓ Cert-Manager     — TLS certificate automation"
echo "  ✓ Kyverno          — Policy enforcement"
echo "  ✓ Istio            — Service mesh (mTLS enabled)"
echo "  ✓ AWS LB Controller — ALB provisioning"
echo "  ✓ External Secrets — Secrets Manager sync"
echo "  ✓ Prometheus       — Metrics + alerting"
echo "  ✓ Grafana          — Dashboards"
echo "  ✓ Fluent Bit       — Log shipping to CloudWatch"
echo "  ✓ ArgoCD           — GitOps continuous delivery"
echo ""
echo "Next steps:"
echo "  • Access ArgoCD UI:   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  • Access Grafana UI:  kubectl port-forward svc/prometheus-grafana -n rockauto-monitoring 3000:80"
echo "  • Get ArgoCD password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
