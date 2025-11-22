# Application Gateway Apps

This folder contains FastAPI applications for multi-tenant deployment via Azure Application Gateway and Container Apps.

## Directory Structure

```
app-gtway-apps/
├── nbrly/
│   ├── nbapp1/
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── nbapp2/
│       ├── main.py
│       ├── requirements.txt
│       └── Dockerfile
├── bloom/
│   ├── bmapp1/
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── bmapp2/
│       ├── main.py
│       ├── requirements.txt
│       └── Dockerfile
└── scripts/
    ├── build-and-push-acr.sh
    └── deploy-container-apps.sh
```

## Applications

### NBRLY Tenant
- **nbapp1**: FastAPI app with root URL `/app1`
- **nbapp2**: FastAPI app with root URL `/app2`

### BLOOM Tenant
- **bmapp1**: FastAPI app with root URL `/app1`
- **bmapp2**: FastAPI app with root URL `/app2`

## Network Flow

### Domain-Based Routing
- DNS resolves `https://nbrly-dev.astrapia.io` and `https://bloom-dev.astrapia.io` to Application Gateway
- Application Gateway routes requests based on domain to respective Container App Environments
- Container App Environment routes requests based on path to respective Container Apps

### Request Flow Example
1. Client requests `https://nbrly-dev.astrapia.io/app1`
2. DNS resolves to Application Gateway
3. Application Gateway routes to `ca-env-nbrly-dev` Container App Environment
4. Container App Environment routes to `nbapp1` Container App
5. `nbapp1` handles request at `/app1` endpoint

## Deployment Prerequisites

1. Azure CLI installed and authenticated
2. Docker installed
3. ACR (Azure Container Registry) created
4. Container App Environments created (nbrly and bloom tenants)
5. Application Gateway configured

## Environment Setup

1. Copy `.env.example` to `.env` and update values:
   ```bash
   cp .env.example .env
   ```

2. Update environment variables:
   ```bash
   export ACR_REGISTRY_NAME="your-acr-name"
   export ACR_REGISTRY_URL="your-acr-name.azurecr.io"
   export RESOURCE_GROUP="your-resource-group"
   export ENVIRONMENT="dev"
   export IMAGE_TAG="latest"
   ```

## Build and Push Images

```bash
chmod +x scripts/build-and-push-acr.sh
./scripts/build-and-push-acr.sh
```

## Deploy to Container Apps

```bash
chmod +x scripts/deploy-container-apps.sh
./scripts/deploy-container-apps.sh
```

## Local Testing

### Test nbapp1
```bash
cd nbrly/nbapp1
pip install -r requirements.txt
python main.py
# Access at http://localhost:8000/app1
```

### Test nbapp2
```bash
cd nbrly/nbapp2
pip install -r requirements.txt
python main.py
# Access at http://localhost:8000/app2
```

### Test bmapp1
```bash
cd bloom/bmapp1
pip install -r requirements.txt
python main.py
# Access at http://localhost:8000/app1
```

### Test bmapp2
```bash
cd bloom/bmapp2
pip install -r requirements.txt
python main.py
# Access at http://localhost:8000/app2
```

## Security Best Practices

- ✅ Non-root user in Docker containers
- ✅ Health checks configured
- ✅ Managed identities for ACR access
- ✅ Environment-based configuration
- ✅ Logging configured in applications
- ✅ TLS/HTTPS via Application Gateway
- ✅ Private ingress for internal communication

## Testing Endpoints

- Health: `GET /app{1,2}/health`
- Info: `GET /app{1,2}/info`
- Root: `GET /app{1,2}`

## Monitoring and Logging

- Container App logs: `az containerapp logs show --resource-group RG --name APP_NAME`
- Application Gateway logs: Configured in Azure Portal
- Application logs: Forwarded to Container Apps environment

## Troubleshooting

### Image not found in ACR
- Verify ACR login: `az acr login --name ACR_NAME`
- Check image exists: `az acr repository list --name ACR_NAME`

### Container App not starting
- Check logs: `az containerapp logs show --resource-group RG --name APP_NAME`
- Verify image URL matches ACR repository

### Application Gateway routing issues
- Verify backend pool configuration
- Check HTTP settings
- Review routing rules in Azure Portal
