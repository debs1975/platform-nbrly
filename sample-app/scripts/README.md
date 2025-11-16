# Deployment Scripts Reference

This directory contains scripts for building and deploying the sample application to Azure Container Apps.

## Scripts Overview

### 🚀 deploy.sh (Complete Deployment)
**Purpose:** All-in-one deployment - builds, pushes, and deploys  
**Usage:** `./deploy.sh <app-name> [environment] [tag]`  
**Example:**
```bash
./deploy.sh app1              # Deploy app1 to dev with latest tag
./deploy.sh app2 dev          # Deploy app2 to dev with default tag
./deploy.sh app1 prod v1.2.3  # Deploy app1 to prod with custom tag
```

**What it does:**
1. Calls `build-push.sh` to build and push image
2. Calls `deploy-app.sh` to deploy Container App
3. Shows final deployment status

---

### 🐳 build-push.sh (Image Build & Push)
**Purpose:** Build Docker image and push to Azure Container Registry  
**Usage:** `./build-push.sh <app-name> [environment] [tag]`  
**Example:**
```bash
./build-push.sh app1              # Build app1 for dev with default tag
./build-push.sh app2 staging      # Build app2 for staging with default tag
./build-push.sh app1 prod v1.2.3  # Build app1 for prod with custom tag v1.2.3
```

**What it does:**
1. ✅ Loads configuration from config files (app1-config-{env}.json or app2-config-{env}.json)
2. ✅ Verifies Azure Container Registry exists
3. ✅ Builds Docker image with specified tag
4. ✅ Also tags as 'latest'
5. ✅ Logs into ACR
6. ✅ Pushes both tags to ACR
7. ✅ Shows available tags in ACR

**Key Features:**
- Uses `--build-arg ENVIRONMENT` for environment-specific builds
- Creates both versioned tag and 'latest' tag
- Validates ACR exists before building
- Shows image digest after push

---

### 📦 deploy-app.sh (Container App Deployment)
**Purpose:** Deploy/update Container App (without building image)  
**Usage:** `./deploy-app.sh <app-name> [environment] [tag]`  
**Example:**
```bash
./deploy-app.sh app1              # Deploy app1 with default tag to dev
./deploy-app.sh app2 prod v1.2.3  # Deploy app2 specific version to prod
./deploy-app.sh app1 staging      # Deploy app1 latest staging image
```

**What it does:**
1. ✅ Loads configuration from config files (app1-config-{env}.json or app2-config-{env}.json)
2. ✅ Verifies infrastructure exists (RG, ACR, CAE)
3. ✅ Verifies image exists in ACR
4. ✅ Creates new Container App or updates existing one
5. ✅ Applies environment-specific configuration
6. ✅ Shows application URL and endpoints

**Configuration Applied:**
- CPU and memory from config
- Min/max replicas from config
- Environment variables
- Key Vault secret references
- Managed identity
- Health probes (from config in YAML variant)

**Use Cases:**
- ✅ Rollback to previous version
- ✅ Deploy pre-built image from CI/CD
- ✅ Promote image from dev to staging/prod
- ✅ Deploy without rebuilding

---

### 📄 deploy-yaml.sh (YAML-Based Deployment)
**Purpose:** Declarative deployment using YAML manifest  
**Usage:** `./deploy-yaml.sh [environment]`  
**Example:**
```bash
./deploy-yaml.sh dev      # Deploy dev environment
./deploy-yaml.sh staging  # Deploy staging
./deploy-yaml.sh prod     # Deploy production
```

**What it does:**
1. ✅ Builds and pushes Docker image
2. ✅ Generates YAML manifest from template
3. ✅ Substitutes environment-specific variables
4. ✅ Deploys using `az containerapp create --yaml`
5. ✅ Saves generated manifest to `manifests/.generated/`

**Benefits:**
- Full declarative configuration
- GitOps compatible
- Easy to review in PRs
- Version-controlled manifests

---

### 🔄 deploy-routing.sh (HTTP Routing)
**Purpose:** Deploy HTTP routing rules to Container Apps Environment  
**Usage:** `./deploy-routing.sh [environment]`  
**Example:**
```bash
./deploy-routing.sh dev   # Deploy routing for dev environment
```

**What it does:**
- Configures environment-level HTTP routing
- Maps `/app1` prefix to container app
- Preserves path prefix in forwarding

---

### 📊 setup-monitoring.sh (Monitoring & Alerts)
**Purpose:** Configure Application Insights and monitoring alerts  
**Usage:** `./setup-monitoring.sh [environment]`  
**Example:**
```bash
./setup-monitoring.sh dev   # Setup monitoring for dev
```

**What it does:**
- Creates metric-based alerts
- Configures Application Insights integration
- Sets up alert action groups

---

## Workflow Examples

### Standard Development Workflow
```bash
# Deploy app1 to dev
./deploy.sh app1 dev

# Deploy app2 to dev
./deploy.sh app2 dev
```

### CI/CD Pipeline Workflow
```bash
# Step 1: Build and push app1 (run once)
./build-push.sh app1 prod v${BUILD_NUMBER}

# Step 2: Deploy app1 to staging
./deploy-app.sh app1 staging v${BUILD_NUMBER}

# Step 3: After testing, deploy app1 to prod
./deploy-app.sh app1 prod v${BUILD_NUMBER}
```

### Feature Branch Workflow
```bash
# Build app1 feature branch
./build-push.sh app1 dev feature-auth

# Deploy app1 feature branch
./deploy-app.sh app1 dev feature-auth

# Test and merge, then deploy main
./build-push.sh app1 dev latest
./deploy-app.sh app1 dev latest
```

### Rollback Workflow
```bash
# List available versions for app1
az acr repository show-tags --name nbrlydeveastusacr --repository sample-api-app1 --output table

# Deploy previous version
./deploy-app.sh app1 prod v1.1.5
```

### Multi-App Deployment
```bash
# Deploy both apps to dev
./deploy.sh app1 dev
./deploy.sh app2 dev

# Deploy both apps to prod with specific version
./build-push.sh app1 prod v1.2.3
./build-push.sh app2 prod v1.2.3
./deploy-app.sh app1 prod v1.2.3
./deploy-app.sh app2 prod v1.2.3
```

### GitOps Workflow
```bash
# Generate YAML manifests
./deploy-yaml.sh dev
./deploy-yaml.sh staging
./deploy-yaml.sh prod

# Commit generated manifests
git add manifests/.generated/
git commit -m "chore: update container app manifests"

# ArgoCD/Flux will deploy from manifests
```

---

## Script Dependencies

### All Scripts Require:
- ✅ Azure CLI (`az`)
- ✅ jq (JSON processor)
- ✅ Valid Azure credentials

### build-push.sh Additionally Requires:
- ✅ Docker CLI
- ✅ Docker daemon running

### Configuration Files Required:
- ✅ `../config/infra-config-{env}.json` (infrastructure config)
- ✅ `../config/app1-config-{env}.json` (app1 application config)
- ✅ `../config/app2-config-{env}.json` (app2 application config)

---

## Configuration Sources

### Infrastructure Config (`config/infra-config-{env}.json`)
- Project name
- Environment
- Location
- Subscription ID
- Resource names (RG, ACR, CAE, UAMI, KV)

### Application Config (`config/app1-config-{env}.json` or `config/app2-config-{env}.json`)
- Container image name and tag
- Resource limits (CPU, memory)
- Scaling rules (min/max replicas, triggers)
- Health probe configuration
- Environment variables
- Tags

---

## Error Handling

All scripts include:
- ✅ `set -e` - Exit on error
- ✅ Configuration file validation
- ✅ Infrastructure existence checks
- ✅ Image existence verification (deploy-app.sh)
- ✅ Helpful error messages with remediation steps

---

## Best Practices

### During Development
```bash
# Deploy app1 with default settings
./deploy.sh app1 dev

# Deploy app2 with default settings
./deploy.sh app2 dev
```

### For Production Releases
```bash
# Use semantic versioning for app1
./build-push.sh app1 prod v1.2.3
./deploy-app.sh app1 prod v1.2.3

# Use semantic versioning for app2
./build-push.sh app2 prod v1.2.3
./deploy-app.sh app2 prod v1.2.3
```

### For Testing Specific Builds
```bash
# Build app1 once, deploy multiple times
./build-push.sh app1 staging build-456
./deploy-app.sh app1 staging build-456

# Test, then promote
./deploy-app.sh app1 prod build-456
```

### For Quick Updates
```bash
# If image already exists in ACR
./deploy-app.sh app1 dev latest
./deploy-app.sh app2 dev latest
```

---

## Troubleshooting

### "Image not found in ACR"
```bash
# Build and push app1 first
./build-push.sh app1 dev

# Then deploy app1
./deploy-app.sh app1 dev
```

### "Infrastructure not found"
```bash
# Run infrastructure deployment
cd ../../iac-cli/scripts
./01-deploy-networking.sh dev
./02-deploy-security.sh dev
./03-deploy-compute.sh dev
```

### "Permission denied"
```bash
# Make scripts executable
chmod +x scripts/*.sh
```

### Check deployment status
```bash
# View logs
az containerapp logs show --name nbrly-dev-eastus-sample-api-ca -g nbrly-dev-eastus-rg --follow

# View revisions
az containerapp revision list --name nbrly-dev-eastus-sample-api-ca -g nbrly-dev-eastus-rg --output table
```

---

## Related Documentation

- [Main README](../README.md) - Application overview
- [Deployment Guide](../docs/deployment.md) - Detailed deployment instructions
- [Configuration Guide](../docs/configuration.md) - Config file reference
- [Manifests Guide](../docs/manifests.md) - YAML manifest reference
