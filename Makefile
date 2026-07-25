################################################################################
# Makefile — Developer Experience Commands
#
# Why a Makefile?
# - Single entry point for all common operations
# - No one has to remember long terraform/kubectl commands
# - New team members can run `make help` to see all available actions
# - Consistent execution (same command on every developer's machine)
#
# Usage:
#   make bootstrap    → Create S3 bucket and DynamoDB for state
#   make init         → Initialize Terraform
#   make plan         → Preview infrastructure changes
#   make apply        → Deploy infrastructure
#   make destroy      → Tear down everything
#   make kubeconfig   → Configure kubectl for the cluster
################################################################################

.PHONY: help bootstrap init plan apply destroy kubeconfig platform-services verify clean

ENV ?= prod
TF_DIR = terraform
BOOTSTRAP_DIR = terraform/bootstrap
CLUSTER_NAME = rockauto-eks-$(ENV)
AWS_REGION = us-east-1

help: ## Show this help message
	@echo "RockAuto Platform — Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

#===============================================================================
# INFRASTRUCTURE
#===============================================================================

bootstrap: ## Create S3 + DynamoDB for Terraform remote state (run once)
	cd $(BOOTSTRAP_DIR) && terraform init && terraform apply -auto-approve

init: ## Initialize Terraform (download providers, connect to backend)
	cd $(TF_DIR) && terraform init

plan: ## Preview what Terraform will create/change/destroy
	cd $(TF_DIR) && terraform plan -out=tfplan

apply: ## Apply the Terraform plan (deploy infrastructure)
	cd $(TF_DIR) && terraform apply tfplan

destroy: ## DESTROY all infrastructure (saves cost — irreversible!)
	cd $(TF_DIR) && terraform destroy -auto-approve

#===============================================================================
# KUBERNETES
#===============================================================================

kubeconfig: ## Configure kubectl to connect to the EKS cluster
	aws eks update-kubeconfig --name $(CLUSTER_NAME) --region $(AWS_REGION)

platform-services: ## Deploy all platform services (ArgoCD, Istio, Prometheus, etc.)
	./scripts/deploy-platform-services.sh

#===============================================================================
# VALIDATION
#===============================================================================

verify: ## Verify the cluster and platform services are healthy
	@echo "=== Cluster Nodes ==="
	kubectl get nodes
	@echo ""
	@echo "=== System Pods ==="
	kubectl get pods -A | grep -v "Running\|Completed" || echo "All pods healthy!"
	@echo ""
	@echo "=== ArgoCD Apps ==="
	kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD not yet installed"
	@echo ""
	@echo "=== Kyverno Policies ==="
	kubectl get cpol 2>/dev/null || echo "Kyverno not yet installed"

#===============================================================================
# CLEANUP
#===============================================================================

clean: ## Remove local Terraform files (plan, cache)
	rm -f $(TF_DIR)/tfplan
	rm -rf $(TF_DIR)/.terraform
	rm -f $(TF_DIR)/.terraform.lock.hcl
