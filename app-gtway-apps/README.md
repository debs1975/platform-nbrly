# Application Gateway Multi-Tenant Apps

This directory contains FastAPI applications for multi-tenant deployment across NBRLY and BLOOM tenants with path-based routing through the Application Gateway.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Internet Users                            │
│                        (HTTPS Access)                            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
      ┌──────────────────────────────────────────────┐
      │   Azure Application Gateway (WAF_v2)         │
      │   Public IP: *.astrapia.io                  │
      │   SSL/TLS Termination                        │
      └────────┬──────────────────────────────────────┘
               │
      ┌────────┴───────────────────────────────────────┐
      │                                                │
      ▼                                                ▼
┌─────────────────────┐                    ┌──────────────────────┐
│  NBRLY Tenant       │                    │  BLOOM Tenant        │
│  Container Apps     │                    │  Container Apps      │
│  (Internal Only)    │                    │  (Internal Only)     │
│                     │                    │                      │
│ Path-Based Routes:  │                    │ Path-Based Routes:   │
│ ├─ /nbapp1 ─────▶   │                    │ ├─ /bmapp1 ─────▶    │
│ │  (App1 - Items)   │                    │ │  (App1 - Products) │
│ └─ /nbapp2 ─────▶   │                    │ └─ /bmapp2 ─────▶    │
│    (App2 - Tasks)   │                    │    (App2 - Users)    │
└─────────────────────┘                    └──────────────────────┘
```

## Directory Structure

```
app-gtway-apps/
├── requirements.txt                    # Shared Python dependencies
├── Dockerfile.nbapp1                   # NBRLY App1 Docker build
├── Dockerfile.nbapp2                   # NBRLY App2 Docker build
├── Dockerfile.bmapp1                   # BLOOM App1 Docker build
├── Dockerfile.bmapp2                   # BLOOM App2 Docker build
├── nbrly/
│   ├── nbapp1/
│   │   └── main.py                     # NBRLY App1 FastAPI app (Items API)
│   └── nbapp2/
│       └── main.py                     # NBRLY App2 FastAPI app (Tasks API)
├── bloom/
│   ├── bmapp1/
│   │   └── main.py                     # BLOOM App1 FastAPI app (Products API)
│   └── bmapp2/
│       └── main.py                     # BLOOM App2 FastAPI app (Users API)
└── scripts/
    ├── build-push-nbrly.sh             # Build & push NBRLY images
    ├── build-push-bloom.sh             # Build & push BLOOM images
    ├── deploy-apps-nbrly.sh            # Deploy NBRLY apps to Container Apps
    ├── deploy-apps-bloom.sh            # Deploy BLOOM apps to Container Apps
    ├── configure-routing-nbrly.sh      # Configure App Gateway path-based routing for NBRLY
    └── configure-routing-bloom.sh      # Configure App Gateway path-based routing for BLOOM
```

## Applications Overview

### NBRLY Tenant

**NBAPP1** - Items API (Port 8000)
- Root Path: `/nbapp1`
- Endpoints:
  - `GET /nbapp1/` - Root endpoint
  - `GET /nbapp1/health` - Health check
  - `GET /nbapp1/health/ready` - Readiness probe
  - `GET /nbapp1/health/live` - Liveness probe
  - `GET /nbapp1/api/info` - App info
  - `GET /nbapp1/api/items` - List items
  - `GET /nbapp1/api/items/{item_id}` - Get item by ID

**NBAPP2** - Tasks API (Port 8001)
- Root Path: `/nbapp2`
- Endpoints:
  - `GET /nbapp2/` - Root endpoint
  - `GET /nbapp2/health` - Health check
  - `GET /nbapp2/health/ready` - Readiness probe
  - `GET /nbapp2/health/live` - Liveness probe
  - `GET /nbapp2/api/info` - App info
  - `GET /nbapp2/api/tasks` - List tasks
  - `POST /nbapp2/api/tasks` - Create task
  - `GET /nbapp2/api/tasks/{task_id}` - Get task
  - `PUT /nbapp2/api/tasks/{task_id}` - Update task
  - `DELETE /nbapp2/api/tasks/{task_id}` - Delete task

### BLOOM Tenant

**BMAPP1** - Products API (Port 8000)
- Root Path: `/bmapp1`
- Endpoints:
  - `GET /bmapp1/` - Root endpoint
  - `GET /bmapp1/health` - Health check
  - `GET /bmapp1/health/ready` - Readiness probe
  - `GET /bmapp1/health/live` - Liveness probe
  - `GET /bmapp1/api/info` - App info
  - `GET /bmapp1/api/products` - List products
  - `GET /bmapp1/api/products/{product_id}` - Get product by ID

**BMAPP2** - Users API (Port 8001)
- Root Path: `/bmapp2`
- Endpoints:
  - `GET /bmapp2/` - Root endpoint
  - `GET /bmapp2/health` - Health check
  - `GET /bmapp2/health/ready` - Readiness probe
  - `GET /bmapp2/health/live` - Liveness probe
  - `GET /bmapp2/api/info` - App info
  - `GET /bmapp2/api/users` - List users
  - `POST /bmapp2/api/users` - Create user
  - `GET /bmapp2/api/users/{user_id}` - Get user
  - `PUT /bmapp2/api/users/{user_id}` - Update user
  - `DELETE /bmapp2/api/users/{user_id}` - Delete user

## Prerequisites

Before deploying, ensure the following are completed:

1. **Infrastructure deployed** - Run the IaC deployment scripts:
   ```bash
   cd ../../iac-cli/scripts
   ./00-deploy-all.sh
   ```

2. **Docker installed** - Required for building container images

3. **Azure CLI installed** - For pushing images to ACR and deploying apps

4. **Azure authenticated** - Run `az login` to authenticate

## Deployment Workflow

### Step 1: Build and Push Images to ACR

**For NBRLY tenant apps:**
```bash
cd app-gtway-apps
./scripts/build-push-nbrly.sh dev latest
```

**For BLOOM tenant apps:**
```bash
./scripts/build-push-bloom.sh dev latest
```

**What this does:**
- Builds Docker images for nbapp1, nbapp2, bmapp1, bmapp2
- Tags them with the specified environment and version
- Pushes them to Azure Container Registry (ACR)

### Step 2: Deploy Apps to Container App Environments

**Deploy NBRLY apps:**
```bash
./scripts/deploy-apps-nbrly.sh dev latest
```

**Deploy BLOOM apps:**
```bash
./scripts/deploy-apps-bloom.sh dev latest
```

**What this does:**
- Creates Container App resources for each application
- Configures internal ingress (not externally accessible directly)
- Sets up environment variables and resource limits
- Integrates with managed identity for ACR access

### Step 3: Configure Application Gateway Path-Based Routing

**Configure NBRLY routing:**
```bash
./scripts/configure-routing-nbrly.sh
```

**Configure BLOOM routing:**
```bash
./scripts/configure-routing-bloom.sh
```

**What this does:**
- Creates backend pools pointing to Container App Environments
- Creates URL path maps for path-based routing
- Configures HTTP settings with proper host headers
- Enables path-based routing on the Application Gateway

## Naming Conventions

The implementation follows these naming conventions (as per `azure-ca-appgtwy.md`):

```
{project}-{environment}-{region}-{service}-{resource-type}
```

Examples:
- **Image Names:**
  - `nbrly-tenant-nbapp1:latest` (NBRLY App1)
  - `nbrly-tenant-nbapp2:latest` (NBRLY App2)
  - `bloom-tenant-bmapp1:latest` (BLOOM App1)
  - `bloom-tenant-bmapp2:latest` (BLOOM App2)

- **Container App Names:**
  - `nbrly-dev-eastus-nbapp1-ca` (NBRLY App1)
  - `nbrly-dev-eastus-nbapp2-ca` (NBRLY App2)
  - `bloom-dev-eastus-bmapp1-ca` (BLOOM App1)
  - `bloom-dev-eastus-bmapp2-ca` (BLOOM App2)

- **Application Gateway Resources:**
  - `nbrly-cae-bp` (Backend pool)
  - `nbrly-cae-upm` (URL path map)
  - `bloom-cae-bp` (Backend pool)
  - `bloom-cae-upm` (URL path map)

## Complete Deployment Script

To execute all steps at once, create and run:

```bash
#!/bin/bash
set -e

cd app-gtway-apps

# Build and push images
echo "Building and pushing NBRLY apps..."
./scripts/build-push-nbrly.sh dev latest

echo "Building and pushing BLOOM apps..."
./scripts/build-push-bloom.sh dev latest

# Deploy apps
echo "Deploying NBRLY apps..."
./scripts/deploy-apps-nbrly.sh dev latest

echo "Deploying BLOOM apps..."
./scripts/deploy-apps-bloom.sh dev latest

# Configure routing
echo "Configuring NBRLY routing..."
./scripts/configure-routing-nbrly.sh

echo "Configuring BLOOM routing..."
./scripts/configure-routing-bloom.sh

echo "Deployment complete!"
```

## Accessing Applications

Once deployed, access your applications via these URLs:

**NBRLY Tenant:**
- App1 (Items): `https://nbrly-dev.astrapia.io/nbapp1`
- App2 (Tasks): `https://nbrly-dev.astrapia.io/nbapp2`

**BLOOM Tenant:**
- App1 (Products): `https://bloom-dev.astrapia.io/bmapp1`
- App2 (Users): `https://bloom-dev.astrapia.io/bmapp2`

## Testing Applications

### Test NBRLY App1 (Items API)

```bash
# Get items
curl -s "https://nbrly-dev.astrapia.io/nbapp1/api/items" | jq

# Get specific item
curl -s "https://nbrly-dev.astrapia.io/nbapp1/api/items/1" | jq

# Health check
curl -s "https://nbrly-dev.astrapia.io/nbapp1/health" | jq
```

### Test NBRLY App2 (Tasks API)

```bash
# List tasks
curl -s "https://nbrly-dev.astrapia.io/nbapp2/api/tasks" | jq

# Create task
curl -X POST "https://nbrly-dev.astrapia.io/nbapp2/api/tasks" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Task","description":"Test","completed":false}' | jq

# Health check
curl -s "https://nbrly-dev.astrapia.io/nbapp2/health" | jq
```

### Test BLOOM App1 (Products API)

```bash
# Get products
curl -s "https://bloom-dev.astrapia.io/bmapp1/api/products" | jq

# Get specific product
curl -s "https://bloom-dev.astrapia.io/bmapp1/api/products/1" | jq
```

### Test BLOOM App2 (Users API)

```bash
# List users
curl -s "https://bloom-dev.astrapia.io/bmapp2/api/users" | jq

# Create user
curl -X POST "https://bloom-dev.astrapia.io/bmapp2/api/users" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","full_name":"Test User"}' | jq
```

## Docker Build Details

Each Dockerfile uses a multi-stage build process:

1. **Builder Stage**: Installs Python dependencies in a temporary image
2. **Runtime Stage**: Copies dependencies from builder and runs the application

Benefits:
- ✅ Minimal final image size
- ✅ Non-root user execution (security)
- ✅ Optimized for production

Example (NBAPP1):
```dockerfile
# Stage 1: Builder
FROM python:3.11-slim as builder
# ... install dependencies ...

# Stage 2: Runtime
FROM python:3.11-slim
# ... copy from builder, run app as non-root ...
```

## Container App Configuration

Each Container App is configured with:

- **Ingress**: Internal only (not accessible from internet)
- **CPU**: 0.5 cores
- **Memory**: 1.0 Gi
- **Min Replicas**: 0 (scale to zero when idle)
- **Max Replicas**: 5
- **Health Probes**:
  - Startup: `/health`
  - Readiness: `/health/ready`
  - Liveness: `/health/live`

## Troubleshooting

### Images not found in ACR

```bash
# List images in ACR
az acr repository list --name nbrlydeveastusacr

# List tags for specific image
az acr repository show-tags --name nbrlydeveastusacr --repository nbrly-tenant-nbapp1
```

### Container Apps not starting

```bash
# Check container app status
az containerapp show --name nbrly-dev-eastus-nbapp1-ca --resource-group nbrly-dev-eastus-rg

# View logs
az containerapp logs show --name nbrly-dev-eastus-nbapp1-ca --resource-group nbrly-dev-eastus-rg --follow
```

### Routing not working

```bash
# Verify Application Gateway configuration
az network application-gateway show --name nbrly-dev-eastus-agw --resource-group nbrly-dev-eastus-rg

# Check backend pool
az network application-gateway address-pool show --gateway-name nbrly-dev-eastus-agw --resource-group nbrly-dev-eastus-rg --name nbrly-cae-bp

# Check URL path map
az network application-gateway url-path-map show --gateway-name nbrly-dev-eastus-agw --resource-group nbrly-dev-eastus-rg --name nbrly-cae-upm
```

## Key Features

✅ **Multi-Tenant Architecture**: Separate tenant namespaces and resources
✅ **Path-Based Routing**: Route traffic based on URL paths (`/nbapp1`, `/nbapp2`, etc.)
✅ **FastAPI**: Modern Python web framework with automatic API documentation
✅ **Docker**: Multi-stage builds for optimized container images
✅ **Managed Identity**: Secure authentication for ACR access
✅ **Health Probes**: Startup, readiness, and liveness checks for Container Apps
✅ **CORS Support**: Configurable cross-origin resource sharing
✅ **Internal Ingress**: Container Apps not directly exposed to internet
✅ **SSL/TLS**: HTTPS termination at Application Gateway
✅ **Auto-Scaling**: Scale to zero and up based on load

## Security Best Practices

- ✅ Non-root container execution
- ✅ Minimal base images (slim variant)
- ✅ Managed identity for authentication
- ✅ No hardcoded credentials
- ✅ Internal-only Container Apps
- ✅ HTTPS-only traffic
- ✅ CORS configuration
- ✅ Health probes for automated recovery

## Next Steps

1. Deploy infrastructure using IaC scripts
2. Build and push application images
3. Deploy Container Apps
4. Configure Application Gateway routing
5. Test applications via HTTPS URLs
6. Monitor logs and metrics
7. Set up CI/CD pipelines for automated deployments
