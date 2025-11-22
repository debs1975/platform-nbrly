# Build and Push Scripts for App Gateway Applications

This directory contains scripts for building Docker images and pushing them to Azure Container Registry (ACR).

## Scripts Overview

### `build-push-all.sh`
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

### `build-push-nbrly.sh`
Builds and pushes only NBRLY tenant applications (nbapp1, nbapp2).

**Usage:**
```bash
./build-push-nbrly.sh [TAG]
```

### `build-push-bloom.sh`
Builds and pushes only BLOOM tenant applications (bmapp1, bmapp2).

**Usage:**
```bash
./build-push-bloom.sh [TAG]
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
./build-push-all.sh

# Build all apps with version tag
./build-push-all.sh v1.2.3

# Build all apps with environment-specific tag
./build-push-all.sh dev-20241215
```

### Build Tenant-Specific Applications
```bash
# Build only NBRLY applications
./build-push-nbrly.sh v1.0.0

# Build only BLOOM applications  
./build-push-bloom.sh v1.0.0
```

### Verify Images in ACR
```bash
# List all images
az acr repository list --name astradevacr --output table

# List tags for specific image
az acr repository show-tags --name astradevacr --repository nbrly-nbapp1 --output table
```