# Deployment and Routing Scripts for App Gateway Applications

This directory contains scripts for building Docker images, pushing them to Azure Container Registry (ACR), deploying to Container Apps, and configuring Application Gateway routing.

## Script Organization

All scripts are numbered sequentially for easy workflow:

### Build and Push (01-03)
- `01-build-push-all.sh` - Build and push all applications
- `02-build-push-nbrly.sh` - Build and push NBRLY tenant only
- `03-build-push-bloom.sh` - Build and push BLOOM tenant only

### Deploy Container Apps (04-06)
- `04-deploy-all.sh` - Deploy all Container Apps
- `05-deploy-nbrly.sh` - Deploy NBRLY tenant only
- `06-deploy-bloom.sh` - Deploy BLOOM tenant only

### Deploy YAML (07-09)
- `07-deploy-yaml.sh` - Deploy using YAML manifests (calls 08 & 09)
- `08-deploy-yaml-nbrly.sh` - Deploy NBRLY apps using YAML
- `09-deploy-yaml-bloom.sh` - Deploy BLOOM apps using YAML

### Configure Routing (10-12)
- `10-configure-routing.sh` - Configure routing for all tenants (calls 11 & 12)
- `11-configure-routing-nbrly.sh` - Configure routing for NBRLY tenant only
- `12-configure-routing-bloom.sh` - Configure routing for BLOOM tenant only

## Scripts Overview

### Build and Push Scripts

#### 01-build-push-all.sh
Builds and pushes all 4 applications (nbrly and bloom tenants) to ACR.

**Usage:**
```bash
./build-push-all.sh [TAG]
```

**Examples:**
```bash
./build-push-all.sh                    # Build with 'latest' tag
./build-push-all.sh v1.0.0             # Build with version tag
./build-push-all.sh dev-$(date +%Y%m%d) # Build with date-based tag
```

#### 02-build-push-nbrly.sh
Builds and pushes only NBRLY tenant applications (nbapp1, nbapp2).

**Usage:**
```bash
./02-build-push-nbrly.sh [TAG]
```

#### 03-build-push-bloom.sh
Builds and pushes only BLOOM tenant applications (bmapp1, bmapp2).

**Usage:**
```bash
./03-build-push-bloom.sh [TAG]
```

#### 07-deploy-yaml.sh
Deploys all Container Apps using YAML manifests by calling tenant-specific scripts.

**What it does:**
- Calls `08-deploy-yaml-nbrly.sh` for NBRLY tenant
- Calls `09-deploy-yaml-bloom.sh` for BLOOM tenant
- Provides unified deployment interface

**Usage:**
```bash
./07-deploy-yaml.sh [TAG]
```

#### 08-deploy-yaml-nbrly.sh
Deploys NBRLY Container Apps using YAML manifests.

**What it does:**
- Generates manifests from templates
- Updates UAMI client IDs and image tags
- Deploys nbrly-nbapp1 and nbrly-nbapp2
- Restores original manifest placeholders

**Usage:**
```bash
./08-deploy-yaml-nbrly.sh [TAG]
```

#### 09-deploy-yaml-bloom.sh
Deploys BLOOM Container Apps using YAML manifests.

**What it does:**
- Generates manifests from templates
- Updates UAMI client IDs and image tags
- Deploys bloom-bmapp1 and bloom-bmapp2
- Restores original manifest placeholders

**Usage:**
```bash
./09-deploy-yaml-bloom.sh [TAG]
```

#### 08-configure-routing.sh
Configures Application Gateway routing for all tenants.

**What it does:**
- Creates backend pools for all Container Apps
- Configures HTTP settings with health probes
- Sets up URL path maps for path-based routing
- Creates HTTP listeners for domain-based routing (nbrly-dev.astrapia.io, bloom-dev.astrapia.io)
- Configures routing rules for both NBRLY and BLOOM tenants

**Usage:**
```bash
./08-configure-routing.sh
```

### Routing Configuration Scripts

#### 10-configure-routing.sh
Configures Application Gateway routing for all tenants by calling tenant-specific scripts.

**What it does:**
- Calls `11-configure-routing-nbrly.sh` for NBRLY tenant
- Calls `12-configure-routing-bloom.sh` for BLOOM tenant
- Provides unified routing configuration interface

**Usage:**
```bash
./10-configure-routing.sh
```

#### 11-configure-routing-nbrly.sh
Configures Application Gateway routing for NBRLY tenant only.

**What it does:**
- Creates backend pools for NBRLY Container Apps (nbapp1, nbapp2)
- Configures HTTP settings with health probes
- Sets up URL path maps for NBRLY path-based routing
- Creates HTTP listener for nbrly-dev.astrapia.io
- Configures routing rules for NBRLY tenant

**Usage:**
```bash
./11-configure-routing-nbrly.sh
```

#### 12-configure-routing-bloom.sh
Configures Application Gateway routing for BLOOM tenant only.

**What it does:**
- Creates backend pools for BLOOM Container Apps (bmapp1, bmapp2)
- Configures HTTP settings with health probes
- Sets up URL path maps for BLOOM path-based routing
- Creates HTTP listener for bloom-dev.astrapia.io
- Configures routing rules for BLOOM tenant

**Usage:**
```bash
./12-configure-routing-bloom.sh
```

## Prerequisites

Before running these scripts, ensure:

1. **Azure CLI Login**
   ```bash
   az login
   ```

2. **Docker Running**
   ```bash
   docker --version
   # Ensure Docker daemon is running
   ```

3. **ACR Access**
   - Access to Azure Container Registry: `astradevacr.azurecr.io`
   - Proper RBAC permissions (AcrPush role)

## Configuration

The scripts use the following configuration:
- **ACR Name:** `astradevacr`
- **Registry URL:** `astradevacr.azurecr.io`
- **Resource Group:** `rg-astrapia-dev`
- **Default Tag:** `latest`

## Image Names

The scripts create the following Docker images:

### NBRLY Tenant
- `astradevacr.azurecr.io/nbrly-nbapp1:TAG`
- `astradevacr.azurecr.io/nbrly-nbapp2:TAG`

### BLOOM Tenant
- `astradevacr.azurecr.io/bloom-bmapp1:TAG`
- `astradevacr.azurecr.io/bloom-bmapp2:TAG`

## Build Process

Each script performs the following steps:
1. Verify Azure CLI login
2. Login to Azure Container Registry
3. Build Docker images using multi-stage Dockerfiles
4. Tag images for ACR
5. Push images to ACR
6. Provide summary of success/failure

## Error Handling

The scripts include comprehensive error handling:
- Exit on any command failure (`set -euo pipefail`)
- Verify prerequisites before building
- Colored output for better visibility
- Detailed logging with timestamps
- Summary of successful/failed builds

## Security Features

- Uses multi-stage Docker builds
- Non-root user in containers
- Minimal base images
- Health checks included
- Secure credential handling via Azure CLI

## Next Steps

After successfully building and pushing images:
1. Use deployment scripts to deploy to Container Apps
2. Configure Application Gateway routing
3. Test the complete flow

## Troubleshooting

### Common Issues

1. **Azure CLI Not Logged In**
   ```bash
   az login
   ```

2. **ACR Access Denied**
   ```bash
   az role assignment create \
     --assignee $(az account show --query user.name --output tsv) \
     --role "AcrPush" \
     --scope "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/rg-astrapia-dev/providers/Microsoft.ContainerRegistry/registries/astradevacr"
   ```

3. **Docker Build Fails**
   - Check Dockerfile syntax
   - Ensure all required files are present
   - Verify Docker daemon is running

4. **Push Fails**
   - Verify ACR login: `az acr login --name astradevacr`
   - Check network connectivity
   - Ensure sufficient ACR storage quota

### Logs

Scripts provide detailed logs with:
- Timestamps
- Color-coded messages (INFO, SUCCESS, WARNING, ERROR)
- Progress indicators
- Summary reports

## Examples

### Build All Applications
```bash
# Build all apps with latest tag
./01-build-push-all.sh

# Build all apps with version tag
./01-build-push-all.sh v1.2.3

# Build all apps with environment-specific tag
./01-build-push-all.sh dev-20241215
```

### Build Tenant-Specific Applications
```bash
# Build only NBRLY applications
./02-build-push-nbrly.sh v1.0.0

# Build only BLOOM applications  
./03-build-push-bloom.sh v1.0.0
```

### Verify Images in ACR
```bash
# List all images
az acr repository list --name astradevacr --output table

# List tags for specific image
az acr repository show-tags --name astradevacr --repository nbrly-nbapp1 --output table
```