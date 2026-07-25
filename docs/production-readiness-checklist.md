# RockAuto - Production Readiness Checklist

## Purpose

This checklist is used by platform engineers to assess workloads before promoting to production. Regional teams use this during design reviews and production readiness assessments.

---

## How to Use

- Complete all sections before requesting production deployment
- Mark items as ✅ (complete), ⚠️ (partial/waiver needed), or ❌ (not done)
- All CRITICAL items must be ✅ — no exceptions
- RECOMMENDED items should be ✅ unless a documented waiver exists

---

## 1. Container & Image Security

| # | Check | Severity | Status |
|---|-------|----------|--------|
| 1.1 | Images built from approved base images (distroless/alpine) | CRITICAL | |
| 1.2 | No HIGH/CRITICAL CVEs in container scan (Trivy) | CRITICAL | |
| 1.3 | Images signed with Cosign and signature verified at admission | CRITICAL | |
| 1.4 | Images pulled from approved registries only (ECR/ACR) | CRITICAL | |
| 1.5 | No root user in container (runAsNonRoot: true) | CRITICAL | |
| 1.6 | Read-only root filesystem enabled | RECOMMENDED | |
| 1.7 | Image tag uses SHA digest (not :latest) | CRITICAL | |
| 1.8 | Multi-stage build used (minimal final image) | RECOMMENDED | |

---

## 2. Kubernetes Workload Configuration

| # | Check | Severity | Status |
|---|-------|----------|--------|
| 2.1 | Resource requests AND limits defined for CPU and memory | CRITICAL | |
| 2.2 | Liveness and readiness probes configured | CRITICAL | |
| 2.3 | Pod Disruption Budget (PDB) defined | CRITICAL | |
| 2.4 | Horizontal Pod Autoscaler (HPA) configured | RECOMMENDED | |
| 2.5 | Anti-affinity rules for high availability | RECOMMENDED | |
| 2.6 | Graceful shutdown handled (preStop hook or SIGTERM handling) | CRITICAL | |
| 2.7 | No hostNetwork, hostPID, or hostIPC | CRITICAL | |
| 2.8 | Security context applied (drop ALL capabilities) | CRITICAL | |
| 2.9 | Service account with minimal RBAC (not default SA) | CRITICAL | |
| 2.10 | Labels applied: app, version, team, environment | CRITICAL | |

---

## 3. Networking & Traffic Management

| # | Check | Severity | Status |
|---|-------|----------|--------|
| 3.1 | Network policies defined (default-deny ingress + egress) | CRITICAL | |
| 3.2 | Service mesh sidecar injected (Istio) | CRITICAL | |
| 3.3 | mTLS enforced for service-to-service communication | CRITICAL | |
| 3.4 | Ingress uses TLS termination with valid certificate | CRITICAL | |
| 3.5 | Rate limiting configured for external-facing services | RECOMMENDED | |
| 3.6 | Circuit breaker / retry policies defined | RECOMMENDED | |
| 3.7 | DNS resolution tested and Service discovery working | CRITICAL | |

---

## 4. Identity & Access Control

| # | Check | Severity | Status |
|---|-------|----------|--------|
| 4.1 | Workload uses IRSA (AWS) or Workload Identity (Azure) | CRITICAL | |
| 4.2 | No long-lived credentials or static access keys | CRITICAL | |
| 4.3 | Secrets stored in external secret store (not in Git/ConfigMaps) | CRITICAL | |
| 4.4 | RBAC follows least-privilege principle | CRITICAL | |
| 4.5 | Service-to-service auth uses mTLS or JWT validation | CRITICAL | |
| 4.6 | Namespace isolation enforced | CRITICAL | |

---

## 5. Observability & Incident Response

| # | Check | Severity | Status |
|---|-------|----------|--------|
| 5.1 | Metrics endpoint exposed (/metrics on port 9090) | CRITICAL | |
| 5.2 | ServiceMonitor or PodMonitor created for Prometheus | CRITICAL | |
| 5.3 | Structured logging (JSON) to stdout/stderr | CRITICAL | |
| 5.4 | Log level configurable via environment variable | RECOMMENDED | |
| 5.5 | Distributed tracing instrumented (OpenTelemetry/Istio) | RECOMMENDED | |
| 5.6 | Grafana dashboard created for key metrics | CRITICAL | |
| 5.7 | Alerting rules defined (error rate, latency, saturation) | CRITICAL | |
| 5.8 | Runbook linked in alert annotations | RECOMMENDED | |
| 5.9 | On-call rotation and escalation path documented | CRITICAL | |
| 5.10 | SLO/SLI defined and measured | RECOMMENDED | |

---

## 6. Reliability & Availability

| # | Check | Severity | Status |
|---|-------|----------|--------|
| 6.1 | Minimum 2 replicas in production | CRITICAL | |
| 6.2 | Deployed across multiple availability zones | CRITICAL | |
| 6.3 | Tested with chaos/failure injection | RECOMMENDED | |
| 6.4 | Rollback procedure documented and tested | CRITICAL | |
| 6.5 | Canary or blue-green deployment strategy configured | RECOMMENDED | |
| 6.6 | Database connection pooling and retry logic | CRITICAL | |
| 6.7 | External dependency timeouts configured | CRITICAL | |

---

## 7. CI/CD & Deployment

| # | Check | Severity | Status |
|---|-------|----------|--------|
| 7.1 | All changes go through GitOps (ArgoCD) | CRITICAL | |
| 7.2 | No manual kubectl apply in production | CRITICAL | |
| 7.3 | Pipeline includes: lint → test → scan → build → deploy | CRITICAL | |
| 7.4 | IaC scanned with Checkov/tfsec | CRITICAL | |
| 7.5 | Promotion requires approval gate (dev → staging → prod) | CRITICAL | |
| 7.6 | Automated rollback on health check failure | RECOMMENDED | |
| 7.7 | Deployment tested in staging with production-like data | RECOMMENDED | |

---

## 8. Edge-Specific Requirements (if applicable)

| # | Check | Severity | Status |
|---|-------|----------|--------|
| 8.1 | Workload can operate in disconnected mode | CRITICAL | |
| 8.2 | Local data buffering when cloud connectivity lost | CRITICAL | |
| 8.3 | Resource footprint validated for edge hardware constraints | CRITICAL | |
| 8.4 | OTA update mechanism tested | CRITICAL | |
| 8.5 | Edge-to-cloud sync validated (eventual consistency) | CRITICAL | |
| 8.6 | Local monitoring/alerting active when disconnected | RECOMMENDED | |

---

## Sign-Off

| Role | Name | Date | Approval |
|------|------|------|----------|
| Platform Engineer | | | |
| Security Reviewer | | | |
| SRE / On-call Lead | | | |
| Product Owner | | | |

---

## Notes & Waivers

Document any items marked ⚠️ with justification and timeline for resolution:

| Item # | Waiver Reason | Resolution Date | Approved By |
|--------|---------------|-----------------|-------------|
| | | | |
