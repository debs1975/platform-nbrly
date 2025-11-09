# Multi-Application Deployment Guide

This sample demonstrates deploying multiple independent FastAPI applications as **separate Docker images** to separate Azure Container Apps instances.

## Architecture

```
┌──────────────────┐        ┌──────────────────┐
│ Dockerfile.app1  │        │ Dockerfile.app2  │
│                  │        │                  │
│ main_app1.py     │        │ main_app2.py     │
│ requirements.txt │        │ requirements.txt │
│ FastAPI /app1/*  │        │ FastAPI /app2/*  │
└────────┬─────────┘        └────────┬─────────┘
         │                           │
         ▼                           ▼
┌──────────────────┐        ┌──────────────────┐
│ sample-api-app1  │        │ sample-api-app2  │
│ (Docker Image)   │        │ (Docker Image)   │
└────────┬─────────┘        └────────┬─────────┘
         │                           │
         ▼                           ▼
┌──────────────────┐        ┌──────────────────┐
│ Container App 1  │        │ Container App 2  │
│                  │        │                  │
│ Image:           │        │ Image:           │
│  sample-api-app1 │        │  sample-api-app2 │
│                  │        │                  │
│ ENV:             │        │ ENV:             │
│  PORT=8000       │        │  PORT=8001       │
│  LOG_LEVEL=INFO  │        │  LOG_LEVEL=INFO  │
│                  │        │                  │
│ Resources:       │        │ Resources:       │
│  CPU: 0.5-2.0    │        │  CPU: 0.5-2.0    │
│  Mem: 1-4Gi      │        │  Mem: 1-4Gi      │
│  Replicas: 0-50  │        │  Replicas: 0-50  │
└──────────────────┘        └──────────────────┘
```

## Applications

### App1 (main_app1.py)
- **Root Path:** `/app1`
- **Port:** `8000`
- **Dockerfile:** `Dockerfile.app1`
- **Image:** `sample-api-app1`
- **Features:**
  - Basic health checks
  - Database connectivity test
  - Configuration info endpoint
  - Secret integration

### App2 (main_app2.py)
- **Root Path:** `/app2`
- **Port:** `8001`
- **Dockerfile:** `Dockerfile.app2`
- **Image:** `sample-api-app2`
- **Features:**
  - All App1 features
  - Task management API (CRUD operations)
  - In-memory data store
  - Additional endpoints

## Configuration Files

Each application has separate configuration files:

```
config/
├── app-config-dev.json          # App1 dev config
├── app-config-staging.json      # App1 staging config
├── app-config-prod.json         # App1 prod config
├── app2-config-dev.json         # App2 dev config
├── app2-config-staging.json     # App2 staging config
└── app2-config-prod.json        # App2 prod config
```

### Key Configuration Differences

| Setting | App1 | App2 |
|---------|------|------|
| Image Name | `sample-api-app1` | `sample-api-app2` |
| Dockerfile | `Dockerfile.app1` | `Dockerfile.app2` |
| Container Name | `sample-api-ca` | `sample-api-v2-ca` |
| Port | 8000 | 8001 |
| Root Path | `/app1` | `/app2` |
| Health Probes | `/app1/health/*` | `/app2/health/*` |
| Display Name | "Sample API" | "Sample API v2" |

## Deployment

### Deploy Both Applications

```bash
# Build and push App1 image
./scripts/build-push.sh dev latest app

# Build and push App2 image
./scripts/build-push.sh dev latest app2

# Deploy App1
./scripts/deploy-app.sh dev latest app

# Deploy App2
./scripts/deploy-app.sh dev latest app2
```

### Deploy App1 Only

```bash
./scripts/deploy.sh dev latest app
```

### Deploy App2 Only

```bash
./scripts/deploy.sh dev latest app2
```

### Deploy to Different Environments

```bash
# Development
./scripts/deploy.sh dev latest app
./scripts/deploy.sh dev latest app2

# Staging
./scripts/deploy.sh staging latest app
./scripts/deploy.sh staging latest app2

# Production with versioned tag
./scripts/deploy.sh prod v1.2.3 app
./scripts/deploy.sh prod v1.2.3 app2
```

## Testing Applications

### App1 Endpoints

```bash
# Get App1 FQDN
APP1_FQDN=$(az containerapp show \
  --name nbrly-dev-eastus-sample-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.configuration.ingress.fqdn -o tsv)

# Test endpoints
curl https://${APP1_FQDN}/app1/health
curl https://${APP1_FQDN}/app1/health/ready
curl https://${APP1_FQDN}/app1/api/info
curl https://${APP1_FQDN}/app1/docs
```

### App2 Endpoints

```bash
# Get App2 FQDN
APP2_FQDN=$(az containerapp show \
  --name nbrly-dev-eastus-sample-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.configuration.ingress.fqdn -o tsv)

# Test endpoints
curl https://${APP2_FQDN}/app2/health
curl https://${APP2_FQDN}/app2/health/ready
curl https://${APP2_FQDN}/app2/api/info
curl https://${APP2_FQDN}/app2/docs

# Task management
curl https://${APP2_FQDN}/app2/api/tasks
curl -X POST "https://${APP2_FQDN}/app2/api/tasks?title=Test&description=Demo"
curl https://${APP2_FQDN}/app2/api/tasks/1
curl -X PUT "https://${APP2_FQDN}/app2/api/tasks/1?status=completed"
curl -X DELETE "https://${APP2_FQDN}/app2/api/tasks/1"
```

## Environment Variables

Each Docker image has a minimal set of environment variables:

| Variable | App1 Value | App2 Value | Description |
|----------|------------|------------|-------------|
| `PORT` | `8000` | `8001` | Application port |
| `LOG_LEVEL` | Per env | Per env | Logging verbosity |
| `ENVIRONMENT` | Per env | Per env | Environment name |

**Note:** No `APP_MODULE` variable needed - each image hardcodes its app in the CMD.

## Docker Images

Each application has its own dedicated Docker image:

### Dockerfile.app1
```dockerfile
# Multi-stage build for App1
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY main_app1.py .

# Hardcoded for App1
CMD ["uvicorn", "main_app1:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
```

### Dockerfile.app2
```dockerfile
# Multi-stage build for App2
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY main_app2.py .

# Hardcoded for App2
CMD ["uvicorn", "main_app2:app", "--host", "0.0.0.0", "--port", "8001", "--workers", "1"]
```

### Building Locally

```bash
# Build App1 image
docker build -f Dockerfile.app1 -t sample-api-app1:local .

# Build App2 image
docker build -f Dockerfile.app2 -t sample-api-app2:local .

# Run App1
docker run -p 8000:8000 \
  -e ENVIRONMENT=development \
  sample-api-app1:local

# Run App2
docker run -p 8001:8001 \
  -e ENVIRONMENT=development \
  sample-api-app2:local
```

## Benefits of Multi-App Approach

### Separate Images
✅ **True Separation**: Each app has its own dedicated image  
✅ **Smaller Image Size**: Images contain only what they need  
✅ **Independent Builds**: Build and release apps separately  
✅ **Clear Deployment**: No runtime env var selection needed  
✅ **Faster Builds**: Only rebuild changed apps  

### Separate Container Apps
✅ **Independent Scaling**: Scale each app based on its traffic  
✅ **Separate Monitoring**: Distinct health probes and alerts  
✅ **Resource Isolation**: Different CPU/memory per app  
✅ **Isolated Failures**: One app failure doesn't affect the other  
✅ **Independent Deployments**: Deploy apps on different schedules  

### Configuration Management
✅ **Environment-Specific**: Settings per app and environment  
✅ **Flexible Resources**: Different allocations per app  
✅ **App-Specific Config**: Separate probe timings, ports, paths  
✅ **Version Control**: Track config changes per app  

## Resource Allocation

### Development
| Resource | App1 | App2 |
|----------|------|------|
| CPU | 0.5 cores | 0.5 cores |
| Memory | 1.0Gi | 1.0Gi |
| Min Replicas | 0 | 0 |
| Max Replicas | 10 | 10 |

### Production
| Resource | App1 | App2 |
|----------|------|------|
| CPU | 2.0 cores | 2.0 cores |
| Memory | 4.0Gi | 4.0Gi |
| Min Replicas | 2 | 2 |
| Max Replicas | 50 | 50 |

## Monitoring

Both applications have separate monitoring and alerting:

```bash
# Setup monitoring for App1
./scripts/setup-monitoring.sh dev app

# Setup monitoring for App2
./scripts/setup-monitoring.sh dev app2
```

## Routing

Configure environment-level routing to both apps:

```yaml
# routing.yaml
rules:
  - path: /app1
    action:
      prefixRewrite: /app1
    target:
      containerAppName: nbrly-dev-eastus-sample-api-ca
  
  - path: /app2
    action:
      prefixRewrite: /app2
    target:
      containerAppName: nbrly-dev-eastus-sample-api-v2-ca
```

Deploy routing:
```bash
./scripts/deploy-routing.sh dev
```

Access via environment FQDN:
```bash
ENV_FQDN=$(az containerapp env show \
  --name nbrly-dev-eastus-cae \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.defaultDomain -o tsv)

curl https://${ENV_FQDN}/app1/health
curl https://${ENV_FQDN}/app2/health
```

## Troubleshooting

### Wrong App Running
This shouldn't happen with separate images, but verify the image name:
```bash
az containerapp show \
  --name nbrly-dev-eastus-sample-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --query "properties.template.containers[0].image" -o tsv
```

Expected output: `nbrlydeveastusacr.azurecr.io/sample-api-app2:latest`

### Health Probe Failures
Ensure health probe paths match the app's root path:
- App1: `/app1/health/live`
- App2: `/app2/health/live`

### Port Conflicts
Each app uses a different port:
- App1: 8000
- App2: 8001

### View Logs
```bash
# App1 logs
az containerapp logs show \
  --name nbrly-dev-eastus-sample-api-ca \
  -g nbrly-dev-eastus-rg \
  --follow

# App2 logs
az containerapp logs show \
  --name nbrly-dev-eastus-sample-api-v2-ca \
  -g nbrly-dev-eastus-rg \
  --follow
```

## Best Practices

1. **Build and Deploy Separately**
   ```bash
   # Build both images
   ./scripts/build-push.sh prod v1.2.3 app
   ./scripts/build-push.sh prod v1.2.3 app2
   
   # Deploy independently
   ./scripts/deploy-app.sh prod v1.2.3 app
   ./scripts/deploy-app.sh prod v1.2.3 app2
   ```

2. **Independent Updates**
   ```bash
   # Update only App2 code and rebuild
   vim main_app2.py
   ./scripts/build-push.sh dev latest app2
   ./scripts/deploy-app.sh dev latest app2
   ```

3. **Version Independently**
   ```bash
   # Deploy different versions per app
   ./scripts/deploy-app.sh prod v1.2.3 app
   ./scripts/deploy-app.sh prod v1.3.0 app2
   ```

4. **Resource Optimization**
   - Use scale-to-zero for dev environments
   - Higher min replicas for production
   - Adjust based on actual usage patterns per app

## Related Documentation

- [Main README](README.md) - Overall application guide
- [Deployment Scripts](scripts/README.md) - Script reference
- [Configuration Guide](docs/configuration.md) - Config file details
