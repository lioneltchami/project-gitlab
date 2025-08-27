# Shakespeare App Deployment Makefile

# Variables
PROJECT_ID ?= my-first-gcp-project
IMAGE_NAME = gcr.io/$(PROJECT_ID)/shakespeare-app
DOCKER_TAG ?= latest
ENVIRONMENT ?= dev
WORD ?= the

# Available words for testing
AVAILABLE_WORDS := the COFFEE AND tea

# Help target
.PHONY: help
help: ## Show this help message
	@echo "Shakespeare App Deployment Commands:"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development
.PHONY: dev-setup
dev-setup: ## Set up local development environment
	@echo "Setting up development environment..."
	mkdir -p credentials
	@echo "⚠️  Set your Google Cloud service account key at: credentials/service-account.json"
	@echo "⚠️  Or generate one at: https://console.cloud.google.com/iam-admin/serviceaccounts"
	cp .env.example .env || echo "WORD=the" > .env
	@echo "✅ Development setup complete. Edit .env file with your settings."
	@echo ""
	@echo "📝 Available words for testing: the, COFFEE, AND, tea"

.PHONY: dev-up
dev-up: ## Start local development environment
	docker-compose up --build

.PHONY: dev-down
dev-down: ## Stop local development environment
	docker-compose down

.PHONY: dev-logs
dev-logs: ## View logs from local development environment
	docker-compose logs -f

##@ Testing
.PHONY: test
test: ## Run tests
	python -m py_compile app.py
	python -c "import app; print('✅ App imports successfully')"

.PHONY: security-scan
security-scan: ## Run security scans
	pip install bandit safety
	bandit -r . || true
	safety check || true

.PHONY: lint
lint: ## Run linting
	pip install flake8 black
	flake8 app.py
	black --check app.py

##@ Build
.PHONY: build
build: ## Build Docker image
	docker build -t $(IMAGE_NAME):$(DOCKER_TAG) .
	docker tag $(IMAGE_NAME):$(DOCKER_TAG) $(IMAGE_NAME):latest

.PHONY: push
push: ## Push Docker image to registry
	docker push $(IMAGE_NAME):$(DOCKER_TAG)
	docker push $(IMAGE_NAME):latest

.PHONY: build-push
build-push: build push ## Build and push Docker image

##@ Infrastructure
.PHONY: terraform-init
terraform-init: ## Initialize Terraform
	cd terraform && terraform init

.PHONY: terraform-plan
terraform-plan: ## Plan Terraform changes
	cd terraform && terraform plan -var="project_id=$(PROJECT_ID)" -var="environment=$(ENVIRONMENT)"

.PHONY: terraform-apply
terraform-apply: ## Apply Terraform changes
	cd terraform && terraform apply -var="project_id=$(PROJECT_ID)" -var="environment=$(ENVIRONMENT)"

.PHONY: terraform-destroy
terraform-destroy: ## Destroy Terraform infrastructure
	cd terraform && terraform destroy -var="project_id=$(PROJECT_ID)" -var="environment=$(ENVIRONMENT)"

##@ Deployment
.PHONY: deploy-dev
deploy-dev: ## Deploy to development environment
	@echo "Deploying to development..."
	./scripts/deploy.sh dev $(DOCKER_TAG)

.PHONY: deploy-prod
deploy-prod: ## Deploy to production environment
	@echo "Deploying to production..."
	@read -p "Are you sure you want to deploy to production? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	./scripts/deploy.sh prod $(DOCKER_TAG)

.PHONY: rollback
rollback: ## Rollback deployment
	./scripts/rollback.sh $(ENVIRONMENT)

##@ Helm
.PHONY: helm-lint
helm-lint: ## Lint Helm chart
	helm lint helm/shakespeare

.PHONY: helm-template
helm-template: ## Template Helm chart
	helm template shakespeare helm/shakespeare --values helm/shakespeare/values.yaml

.PHONY: helm-install
helm-install: ## Install Helm chart
	helm upgrade --install shakespeare helm/shakespeare --values helm/shakespeare/values.yaml --create-namespace --namespace shakespeare-$(ENVIRONMENT)

.PHONY: helm-uninstall
helm-uninstall: ## Uninstall Helm chart
	helm uninstall shakespeare --namespace shakespeare-$(ENVIRONMENT)

##@ Monitoring
.PHONY: logs
logs: ## View application logs
	kubectl logs -f -l app=shakespeare -n shakespeare-$(ENVIRONMENT)

.PHONY: status
status: ## Check deployment status
	kubectl get pods,services,ingress -n shakespeare-$(ENVIRONMENT)

.PHONY: port-forward
port-forward: ## Port forward to application
	kubectl port-forward svc/shakespeare-the-service 8080:80 -n shakespeare-$(ENVIRONMENT)

##@ Cleanup
.PHONY: clean
clean: ## Clean up local Docker resources
	docker system prune -f
	docker volume prune -f

.PHONY: clean-all
clean-all: clean ## Clean up everything including images
	docker rmi $(IMAGE_NAME):$(DOCKER_TAG) $(IMAGE_NAME):latest || true