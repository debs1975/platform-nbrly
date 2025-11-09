# Sample FastAPI Application

This directory contains a sample FastAPI application demonstrating deployment to Azure Container Apps.

## Features

- ✅ FastAPI web framework
- ✅ Health check endpoints (health, readiness, liveness)
- ✅ Key Vault secret integration
- ✅ Environment variable configuration
- ✅ Multi-stage Docker build for optimization
- ✅ Non-root container user for security
- ✅ Automatic deployment script

## Application Structure

```
sample-app/
├── main.py              # FastAPI application
├── requirements.txt     # Python dependencies
├── Dockerfile          # Multi-stage Docker build
├── .dockerignore       # Docker build exclusions
├── .gitignore          # Git exclusions
├── scripts/
│   ├── deploy.sh       # Deployment automation script
│   └── setup-monitoring.sh  # Monitoring & alerts configuration
├── docs/
│   └── monitoring-alerts.md  # Alert configurations and runbooks
└── README.md           # This file
```

## Prerequisites

Before deploying, ensure infrastructure is deployed:

```bash
# From repository root
cd scripts
./01-deploy-networking.sh
./02-deploy-security.sh
./03-deploy-compute.sh
./04-deploy-data.sh
./05-deploy-monitoring.sh
```

## Local Development

### Run locally with Python

```bash
cd sample-app

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export ENVIRONMENT=development
export ALLOWED_ORIGINS="*"

# Run application
python main.py
```

Access at: http://localhost:8000

### Run locally with Docker

```bash
cd sample-app

# Build image
docker build -t sample-api:latest .

# Run container
docker run -p 8000:8000 \
  -e ENVIRONMENT=development \
  -e ALLOWED_ORIGINS="*" \
  sample-api:latest
```

Access at: http://localhost:8000

## Deployment to Azure

### Automated Deployment

```bash
cd sample-app

# Deploy to development environment
./scripts/deploy.sh dev

# Deploy to staging
./scripts/deploy.sh staging

# Deploy to production
./scripts/deploy.sh prod
```

This script:
1. Verifies infrastructure exists
2. Builds Docker image
3. Pushes to Azure Container Registry
4. Creates or updates Container App
5. Configures secrets from Key Vault

### Configure Monitoring & Alerts

After deploying the application, set up monitoring:

```bash
cd sample-app

# Configure Application Insights and alerts
./scripts/setup-monitoring.sh dev
```

This creates:
- Application Insights integration
- High restart count alert
- High CPU/memory usage alerts
- HTTP latency and error rate alerts
- Scale-to-zero monitoring

See [docs/monitoring-alerts.md](docs/monitoring-alerts.md) for alert details and investigation runbooks.

### Manual Deployment Steps

If you prefer manual deployment:

```bash
# 1. Set variables
PROJECT_NAME="nbrly"
ENV="dev"
ACR_NAME="${PROJECT_NAME}${ENV}eastusacr"
APP_NAME="${PROJECT_NAME}-${ENV}-eastus-api-ca"
RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"
CAE_NAME="${PROJECT_NAME}-${ENV}-eastus-cae"

# 2. Build and push image
az acr login --name $ACR_NAME
docker build -t ${ACR_NAME}.azurecr.io/sample-api:latest .
docker push ${ACR_NAME}.azurecr.io/sample-api:latest

# 3. Create Container App
az containerapp create \
  --resource-group $RG_NAME \
  --name $APP_NAME \
  --environment $CAE_NAME \
  --image ${ACR_NAME}.azurecr.io/sample-api:latest \
  --target-port 8000 \
  --ingress external \
  --cpu 0.5 \
  --memory 1.0Gi \
  --min-replicas 0 \
  --max-replicas 5
```

## API Endpoints

### Health Checks

- `GET /health` - Basic health check
- `GET /health/ready` - Readiness probe (checks dependencies)
- `GET /health/live` - Liveness probe (simple alive check)

### Application Endpoints

- `GET /` - Root endpoint
- `GET /api/info` - Application configuration info
- `GET /api/database/test` - Database connectivity test
- `GET /docs` - Interactive API documentation (Swagger UI)
- `GET /redoc` - Alternative API documentation (ReDoc)

## Environment Variables

The application uses the following environment variables:

| Variable | Description | Source | Required |
|----------|-------------|--------|----------|
| `ENVIRONMENT` | Environment name (dev/staging/prod) | Direct | Yes |
| `ALLOWED_ORIGINS` | CORS allowed origins (comma-separated) | Direct | No |
| `DATABASE_URL` | PostgreSQL connection string | Key Vault Secret | Yes |
| `SECRET_KEY` | API secret key for JWT signing | Key Vault Secret | Yes |
| `PORT` | Application port (default: 8000) | Direct | No |

## Key Vault Integration

Secrets are automatically injected from Azure Key Vault using managed identity:

```bash
# The Container App references secrets like this:
--secrets \
  "postgres-connection-string=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/postgres-connection-string,identityref:$UAMI_ID" \
  "api-secret-key=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/api-secret-key,identityref:$UAMI_ID"

--env-vars \
  "DATABASE_URL=secretref:postgres-connection-string" \
  "SECRET_KEY=secretref:api-secret-key"
```

## Security Features

- ✅ **Non-root user**: Container runs as `appuser`, not root
- ✅ **Multi-stage build**: Minimal final image size
- ✅ **Managed identity**: No hardcoded credentials
- ✅ **Key Vault secrets**: Secrets injected at runtime
- ✅ **CORS configuration**: Configurable allowed origins
- ✅ **HTTPS only**: Container Apps enforces TLS

## Monitoring

### View Logs

```bash
# Live logs
az containerapp logs show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# Historical logs via Log Analytics
az monitor log-analytics query \
  --workspace nbrly-dev-eastus-law \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'nbrly-dev-eastus-api-ca' | order by TimeGenerated desc | take 100"
```

### View Metrics

Access metrics in Azure Portal:
- Resource Group → Container App → Metrics
- View: Requests, CPU, Memory, Replicas

### Application Insights

The Container App is automatically configured with Application Insights for:
- Request tracking
- Dependency tracking
- Exception tracking
- Custom telemetry

## Scaling Configuration

The Container App is configured for auto-scaling:

```
Min Replicas: 0 (scale to zero when idle)
Max Replicas: 10 (configurable via parameters.json)
Scaling Rules:
  - HTTP requests: Scale at 100 concurrent requests
  - CPU: Scale at 70% utilization
```

## Troubleshooting

### Container App won't start

```bash
# Check provisioning state
az containerapp show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.provisioningState

# Check recent revisions
az containerapp revision list \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg
```

### Image pull errors

```bash
# Verify managed identity has AcrPull role
az role assignment list \
  --assignee $(az identity show --resource-group nbrly-dev-eastus-rg --name nbrly-dev-eastus-uami --query principalId -o tsv)
```

### Secret access errors

```bash
# Verify Key Vault permissions
az keyvault show --name nbrlydeveastuskv --resource-group nbrly-dev-eastus-rg

# Check secrets exist
az keyvault secret list --vault-name nbrlydeveastuskv
```

## Customization

### Add Database Connectivity

Uncomment in `requirements.txt`:
```txt
psycopg2-binary==2.9.9
asyncpg==0.29.0
sqlalchemy==2.0.25
```

Update `main.py` to add actual database connection logic in `/api/database/test`.

### Add More Endpoints

Add new routes in `main.py`:
```python
@app.get("/api/users")
async def get_users():
    return {"users": []}
```

### Change Container Resources

Update in `scripts/deploy.sh`:
```bash
--cpu 1.0 \
--memory 2.0Gi \
--max-replicas 20
```

## Monitoring & Operations

### View Application Insights
```bash
# Get Application Insights URL
APP_INSIGHTS_ID=$(az monitor app-insights component show \
  --app nbrly-dev-eastus-ai \
  --resource-group nbrly-dev-eastus-rg \
  --query id -o tsv)

echo "Application Insights: https://portal.azure.com/#resource${APP_INSIGHTS_ID}/overview"
```

### View Container Logs
```bash
# Stream live logs
az containerapp logs show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# View recent logs
az containerapp logs show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --tail 100
```

### Check Alert Status
```bash
# List all Container App alerts
az monitor metrics alert list \
  --resource-group nbrly-dev-eastus-rg \
  --query "[?contains(name, 'api-ca')]" \
  --output table

# View alert history
az monitor activity-log list \
  --resource-group nbrly-dev-eastus-rg \
  --query "[?contains(category.value, 'Alert')]" \
  --output table
```

For detailed monitoring documentation, see [docs/monitoring-alerts.md](docs/monitoring-alerts.md).

## Next Steps

1. ✅ Deploy infrastructure (scripts/01-05)
2. ✅ Deploy sample app (`./scripts/deploy.sh dev`)
3. ✅ Configure monitoring (`./scripts/setup-monitoring.sh dev`)
4. 🔄 Customize application logic
5. 🔄 Add database connectivity
6. 🔄 Implement authentication
7. 🔄 Add CI/CD pipeline
8. 🔄 Deploy to staging/production

## Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Uvicorn Documentation](https://www.uvicorn.org/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Monitoring & Alerts Guide](docs/monitoring-alerts.md)
