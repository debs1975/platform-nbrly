# Quick Start Guide - Multi-Tenant Application Gateway Apps

## Complete Execution Guide

This guide provides step-by-step instructions to deploy the complete multi-tenant application architecture.

## Prerequisites

✅ Infrastructure deployed (IaC scripts)
✅ Azure CLI installed and authenticated
✅ Docker installed and running
✅ `jq` command-line JSON processor installed

## Complete Deployment (All Steps)

### 1. Prepare Environment

```bash
# Navigate to app-gtway-apps directory
cd app-gtway-apps

# Verify infrastructure state file exists
ls -la ../../iac-cli/config/.generated/generated-infra-dev.json
```

### 2. Build and Push All Images

```bash
# Build and push NBRLY tenant apps
echo "Building NBRLY apps..."
./scripts/build-push-nbrly.sh dev latest

# Build and push BLOOM tenant apps
echo "Building BLOOM apps..."
./scripts/build-push-bloom.sh dev latest
```

**Output:**
- `nbrly-tenant-nbapp1:latest` pushed to ACR
- `nbrly-tenant-nbapp2:latest` pushed to ACR
- `bloom-tenant-bmapp1:latest` pushed to ACR
- `bloom-tenant-bmapp2:latest` pushed to ACR

### 3. Deploy All Applications

```bash
# Deploy NBRLY tenant apps
echo "Deploying NBRLY apps..."
./scripts/deploy-apps-nbrly.sh dev latest

# Deploy BLOOM tenant apps
echo "Deploying BLOOM apps..."
./scripts/deploy-apps-bloom.sh dev latest
```

**Output:**
- 4 Container App resources created
- Each configured with internal ingress
- Auto-scaling enabled (0-5 replicas)
- Managed identity integration complete

### 4. Configure Application Gateway Routing

```bash
# Configure NBRLY routing
echo "Configuring NBRLY routing..."
./scripts/configure-routing-nbrly.sh

# Configure BLOOM routing
echo "Configuring BLOOM routing..."
./scripts/configure-routing-bloom.sh
```

**Output:**
- Path-based routing configured for `/nbapp1/*` and `/nbapp2/*`
- Path-based routing configured for `/bmapp1/*` and `/bmapp2/*`
- Backend pools pointing to Container App Environments
- URL path maps configured

## Verify Deployment

### Check Images in ACR

```bash
# List all images
az acr repository list --name nbrlydeveastusacr --output table

# Expected output should show:
# bloom-tenant-bmapp1
# bloom-tenant-bmapp2
# nbrly-tenant-nbapp1
# nbrly-tenant-nbapp2
```

### Check Container Apps

```bash
# List container apps
az containerapp list --resource-group nbrly-dev-eastus-rg --output table

# Expected: 4 container apps
# nbrly-dev-eastus-nbapp1-ca
# nbrly-dev-eastus-nbapp2-ca
# bloom-dev-eastus-bmapp1-ca
# bloom-dev-eastus-bmapp2-ca
```

### Check Application Gateway Configuration

```bash
# View URL path maps
az network application-gateway url-path-map list \
  --gateway-name nbrly-dev-eastus-agw \
  --resource-group nbrly-dev-eastus-rg \
  --output table

# Expected: Should show nbrly-cae-upm and bloom-cae-upm
```

## Test Endpoints

### Test NBRLY App1 (Items API)

```bash
# Get root
curl -k "https://nbrly-dev.astrapia.io/nbapp1/" | jq

# Get items
curl -k "https://nbrly-dev.astrapia.io/nbapp1/api/items" | jq

# Health check
curl -k "https://nbrly-dev.astrapia.io/nbapp1/health" | jq
```

### Test NBRLY App2 (Tasks API)

```bash
# Get root
curl -k "https://nbrly-dev.astrapia.io/nbapp2/" | jq

# List tasks
curl -k "https://nbrly-dev.astrapia.io/nbapp2/api/tasks" | jq

# Create task
curl -k -X POST "https://nbrly-dev.astrapia.io/nbapp2/api/tasks" \
  -H "Content-Type: application/json" \
  -d '{"title":"Sample Task","description":"Test","completed":false}' | jq

# Health check
curl -k "https://nbrly-dev.astrapia.io/nbapp2/health" | jq
```

### Test BLOOM App1 (Products API)

```bash
# Get root
curl -k "https://bloom-dev.astrapia.io/bmapp1/" | jq

# Get products
curl -k "https://bloom-dev.astrapia.io/bmapp1/api/products" | jq

# Health check
curl -k "https://bloom-dev.astrapia.io/bmapp1/health" | jq
```

### Test BLOOM App2 (Users API)

```bash
# Get root
curl -k "https://bloom-dev.astrapia.io/bmapp2/" | jq

# List users
curl -k "https://bloom-dev.astrapia.io/bmapp2/api/users" | jq

# Create user
curl -k -X POST "https://bloom-dev.astrapia.io/bmapp2/api/users" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","full_name":"Test User"}' | jq

# Health check
curl -k "https://bloom-dev.astrapia.io/bmapp2/health" | jq
```

## Monitoring

### View Container Logs

```bash
# NBRLY App1 logs
az containerapp logs show \
  --name nbrly-dev-eastus-nbapp1-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# NBRLY App2 logs
az containerapp logs show \
  --name nbrly-dev-eastus-nbapp2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# BLOOM App1 logs
az containerapp logs show \
  --name bloom-dev-eastus-bmapp1-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# BLOOM App2 logs
az containerapp logs show \
  --name bloom-dev-eastus-bmapp2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow
```

### View Metrics

```bash
# Check CPU and memory usage
az monitor metrics list \
  --resource nbrly-dev-eastus-nbapp1-ca \
  --resource-group nbrly-dev-eastus-rg \
  --resource-type "Microsoft.App/containerApps" \
  --metric "Requests" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M
```

## Complete Automation Script

Create `deploy-all.sh`:

```bash
#!/bin/bash
set -e

cd app-gtway-apps

echo "=========================================="
echo "Multi-Tenant App Gateway Apps Deployment"
echo "=========================================="

# Step 1: Build and Push
echo ""
echo "[1/4] Building and pushing NBRLY images..."
./scripts/build-push-nbrly.sh dev latest

echo ""
echo "[2/4] Building and pushing BLOOM images..."
./scripts/build-push-bloom.sh dev latest

# Step 2: Deploy
echo ""
echo "[3/4] Deploying NBRLY container apps..."
./scripts/deploy-apps-nbrly.sh dev latest

echo ""
echo "[4/4] Deploying BLOOM container apps..."
./scripts/deploy-apps-bloom.sh dev latest

# Step 3: Configure Routing
echo ""
echo "[5/6] Configuring NBRLY routing..."
./scripts/configure-routing-nbrly.sh

echo ""
echo "[6/6] Configuring BLOOM routing..."
./scripts/configure-routing-bloom.sh

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Access URLs:"
echo "  NBRLY App1: https://nbrly-dev.astrapia.io/nbapp1"
echo "  NBRLY App2: https://nbrly-dev.astrapia.io/nbapp2"
echo "  BLOOM App1: https://bloom-dev.astrapia.io/bmapp1"
echo "  BLOOM App2: https://bloom-dev.astrapia.io/bmapp2"
echo ""
```

Run it:
```bash
chmod +x deploy-all.sh
./deploy-all.sh
```

## Troubleshooting

### "Configuration file not found" Error

```bash
# Ensure IaC deployment was completed
cd ../../iac-cli/scripts
./00-deploy-all.sh
cd ../../app-gtway-apps
```

### ACR Login Fails

```bash
# Check ACR credentials
az acr login --name nbrlydeveastusacr

# If fails, ensure you have permissions
az role assignment list --resource-group nbrly-dev-eastus-rg
```

### Container Apps Won't Start

```bash
# Check image exists
az acr repository show-tags \
  --name nbrlydeveastusacr \
  --repository nbrly-tenant-nbapp1

# Check container app logs
az containerapp logs show \
  --name nbrly-dev-eastus-nbapp1-ca \
  --resource-group nbrly-dev-eastus-rg \
  --tail 50
```

### Routing Not Working

```bash
# Verify Application Gateway listener
az network application-gateway http-listener list \
  --gateway-name nbrly-dev-eastus-agw \
  --resource-group nbrly-dev-eastus-rg \
  --output table

# Verify URL path map
az network application-gateway url-path-map list \
  --gateway-name nbrly-dev-eastus-agw \
  --resource-group nbrly-dev-eastus-rg \
  --output table
```

## Rollback / Cleanup

### Delete Applications Only (Keep Infrastructure)

```bash
# Delete NBRLY container apps
az containerapp delete \
  --name nbrly-dev-eastus-nbapp1-ca \
  --resource-group nbrly-dev-eastus-rg \
  --yes

az containerapp delete \
  --name nbrly-dev-eastus-nbapp2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --yes

# Delete BLOOM container apps
az containerapp delete \
  --name bloom-dev-eastus-bmapp1-ca \
  --resource-group nbrly-dev-eastus-rg \
  --yes

az containerapp delete \
  --name bloom-dev-eastus-bmapp2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --yes

# Delete images from ACR
az acr repository delete \
  --name nbrlydeveastusacr \
  --repository nbrly-tenant-nbapp1 \
  --yes

az acr repository delete \
  --name nbrlydeveastusacr \
  --repository nbrly-tenant-nbapp2 \
  --yes

az acr repository delete \
  --name nbrlydeveastusacr \
  --repository bloom-tenant-bmapp1 \
  --yes

az acr repository delete \
  --name nbrlydeveastusacr \
  --repository bloom-tenant-bmapp2 \
  --yes
```

### Delete Entire Infrastructure

```bash
# Delete resource group (deletes all resources)
az group delete \
  --name nbrly-dev-eastus-rg \
  --yes --no-wait
```

## Success Criteria

✅ All 4 Docker images built and pushed to ACR
✅ All 4 Container Apps created and running
✅ Application Gateway path-based routing configured
✅ All 8 endpoints responding to HTTPS requests
✅ Health checks returning 200 OK
✅ Path-based routing working:
  - `/nbapp1/*` routes to NBRLY App1
  - `/nbapp2/*` routes to NBRLY App2
  - `/bmapp1/*` routes to BLOOM App1
  - `/bmapp2/*` routes to BLOOM App2

## Additional Resources

- **Main Documentation**: `app-gtway-apps/README.md`
- **Implementation Summary**: `IMPLEMENTATION_SUMMARY.md`
- **Architecture Documentation**: `docs/azure-ca-appgtwy-imp-plan.md`
- **IaC Infrastructure**: `iac-cli/scripts/`

---

**Created**: November 18, 2025
**Version**: 1.0
