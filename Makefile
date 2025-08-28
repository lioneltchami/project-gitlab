PROJECT_ID ?= your-gcp-project-id
IMAGE_NAME = gcr.io/$(PROJECT_ID)/shakespeare-app
DOCKER_TAG ?= latest
ENVIRONMENT ?= dev
WORD ?= the

AVAILABLE_WORDS := the coffee and tea

.PHONY: help
help: 
	@echo "Shakespeare App Deployment Commands:"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development
.PHONY: dev-setup
dev-setup:
	@echo "Setting up development environment..."
	mkdir -p credentials
	@echo "⚠️  Please place your Google Cloud service account key at: credentials/service-account.json"
	@echo "⚠️  You can generate one at: https://console.cloud.google.com/iam-admin/serviceaccounts"
	@echo ""
	@echo "📝 Available words for testing: the, COFFEE, AND, tea"
	@echo "💡 Set WORD environment variable to test different words:"
	@echo "   export WORD=COFFEE"
	@echo "   make dev-up"
	@echo ""
	@echo "✅ Development setup complete."

.PHONY: dev-up
dev-up: 
	docker-compose up --build

.PHONY: dev-down
dev-down: 
	docker-compose down

.PHONY: dev-logs
dev-logs: 
	docker-compose logs -f

##@ Testing
.PHONY: test
test: 
	python -m py_compile app.py
	python -c "import app; print('App imports successfully')"

.PHONY: security-scan
security-scan: 
	pip install bandit safety
	bandit -r . || true
	safety scan || true

.PHONY: lint
lint: 
	pip install flake8 black
	flake8 app.py
	black --check app.py

##@ Build
.PHONY: build
build: 
	docker build -t $(IMAGE_NAME):$(DOCKER_TAG) .
	docker tag $(IMAGE_NAME):$(DOCKER_TAG) $(IMAGE_NAME):latest

.PHONY: push
push: 
	docker push $(IMAGE_NAME):$(DOCKER_TAG)
	docker push $(IMAGE_NAME):latest

.PHONY: build-push
build-push: build push 

##@ Infrastructure
.PHONY: terraform-init
terraform-init:
	cd terraform && terraform init

.PHONY: terraform-plan
terraform-plan:
	cd terraform && terraform plan -var="project_id=$(PROJECT_ID)" -var="environment=$(ENVIRONMENT)"

.PHONY: terraform-apply
terraform-apply:
	cd terraform && terraform apply -var="project_id=$(PROJECT_ID)" -var="environment=$(ENVIRONMENT)"

.PHONY: terraform-destroy
terraform-destroy:
	cd terraform && terraform destroy -var="project_id=$(PROJECT_ID)" -var="environment=$(ENVIRONMENT)"

##@ Deployment
.PHONY: deploy-dev
deploy-dev:
	@echo "Deploying to development..."
	./scripts/deploy.sh dev $(DOCKER_TAG)

.PHONY: deploy-prod
deploy-prod:
	@echo "Deploying to production..."
	@read -p "Are you sure you want to deploy to production? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	./scripts/deploy.sh prod $(DOCKER_TAG)

.PHONY: rollback
rollback:
	./scripts/rollback.sh $(ENVIRONMENT)

##@ Helm
.PHONY: helm-lint
helm-lint:
	helm lint helm/shakespeare

.PHONY: helm-template
helm-template:
	helm template shakespeare helm/shakespeare --values helm/shakespeare/values.yaml

.PHONY: helm-install
helm-install:
	helm upgrade --install shakespeare helm/shakespeare --values helm/shakespeare/values.yaml --create-namespace --namespace shakespeare-$(ENVIRONMENT)

.PHONY: helm-uninstall
helm-uninstall:
	helm uninstall shakespeare --namespace shakespeare-$(ENVIRONMENT)

##@ Monitoring
.PHONY: logs
logs:
	kubectl logs -f -l app=shakespeare -n shakespeare-$(ENVIRONMENT)

.PHONY: status
status:
	kubectl get pods,services,ingress -n shakespeare-$(ENVIRONMENT)

.PHONY: port-forward
port-forward:
	kubectl port-forward svc/shakespeare-the-service 8080:80 -n shakespeare-$(ENVIRONMENT)

##@ Cleanup
.PHONY: clean
clean:
	docker system prune -f
	docker volume prune -f

.PHONY: clean-all
clean-all: clean 
	docker rmi $(IMAGE_NAME):$(DOCKER_TAG) $(IMAGE_NAME):latest || true