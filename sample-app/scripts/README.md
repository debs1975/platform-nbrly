# Deployment Scripts Reference

This directory contains scripts for building and deploying the sample application to Azure Container Apps.

## Scripts Overview

### 🚀 deploy.sh (Complete Deployment)
**Purpose:** All-in-one deployment - builds, pushes, and deploys  
**Usage:** `./deploy.sh [environment] [tag]`  
**Example:**
```bash
./deploy.sh dev              # Deploy dev with default tag
./deploy.sh prod v1.2.3      # Deploy prod with custom tag
```

**What it does:**
1. Calls `build-push.sh` to build and push image
2. Calls `deploy-app.sh` to deploy Container App
3. Shows final deployment status

---

### 🐳 build-push.sh (Image Build & Push)
**Purpose:** Build Docker image and push to Azure Container Registry  
**Usage:** `./build-push.sh [environment] [tag]`  
**Example:**
```bash
./build-push.sh dev              # Build with default tag (latest)
./build-push.sh staging          # Build staging with default tag
./build-push.sh prod v1.2.3      # Build prod with custom tag v1.2.3
./build-push.sh dev feature-xyz  # Build dev with feature branch tag
```

**What it does:**
1. ✅ Loads configuration from config files
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
**Usage:** `./deploy-app.sh [environment] [tag]`  
**Example:**
```bash
./deploy-app.sh dev              # Deploy with default tag
./deploy-app.sh prod v1.2.3      # Deploy specific version
./deploy-app.sh staging latest   # Deploy latest staging image
```

**What it does:**
1. ✅ Loads configuration from config files
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
# Complete deployment
./deploy.sh dev
```

### CI/CD Pipeline Workflow
```bash
# Step 1: Build and push (run once)
./build-push.sh prod v${BUILD_NUMBER}

# Step 2: Deploy to staging
./deploy-app.sh staging v${BUILD_NUMBER}

# Step 3: After testing, deploy to prod
./deploy-app.sh prod v${BUILD_NUMBER}
```

### Feature Branch Workflow
```bash
# Build feature branch
./build-push.sh dev feature-auth

# Deploy feature branch
./deploy-app.sh dev feature-auth

# Test and merge, then deploy main
./build-push.sh dev latest
./deploy-app.sh dev latest
```

### Rollback Workflow
```bash
# List available versions
az acr repository show-tags --name nbrlydevevastusacr --repository sample-api --output table

# Deploy previous version
./deploy-app.sh prod v1.1.5
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
- ✅ `../../iac-cli/config/parameters-{env}.json` (infrastructure config)
- ✅ `../config/app-config-{env}.json` (application config)

---

## Configuration Sources

### Infrastructure Config (`iac-cli/config/parameters-{env}.json`)
- Project name
- Environment
- Location
- Subscription ID
- Resource names (RG, ACR, CAE, UAMI, KV)

### Application Config (`config/app-config-{env}.json`)
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
# Use default tags and complete deployment
./deploy.sh dev
```

### For Production Releases
```bash
# Use semantic versioning
./build-push.sh prod v1.2.3
./deploy-app.sh prod v1.2.3
```

### For Testing Specific Builds
```bash
# Build once, deploy multiple times
./build-push.sh staging build-456
./deploy-app.sh staging build-456

# Test, then promote
./deploy-app.sh prod build-456
```

### For Quick Updates
```bash
# If image already exists in ACR
./deploy-app.sh dev latest
```

---

## Troubleshooting

### "Image not found in ACR"
```bash
# Build and push first
./build-push.sh dev

# Then deploy
./deploy-app.sh dev
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
