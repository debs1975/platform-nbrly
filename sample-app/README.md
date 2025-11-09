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
├── config/
│   ├── app-config-dev.json      # Dev environment config
│   ├── app-config-staging.json  # Staging environment config
│   ├── app-config-prod.json     # Production environment config
│   └── README.md               # Configuration documentation
├── manifests/
│   ├── containerapp.yaml    # Container App YAML manifest template
│   ├── routing.yaml         # HTTP routing configuration template
│   └── .generated/          # Generated manifests (gitignored)
├── scripts/
│   ├── deploy.sh            # CLI-based deployment script
│   ├── deploy-yaml.sh       # YAML-based deployment script (recommended)
│   ├── deploy-routing.sh    # HTTP routing deployment script
│   └── setup-monitoring.sh  # Monitoring & alerts configuration
├── docs/
│   ├── configuration.md     # Configuration documentation
│   ├── deployment.md        # Quick deployment reference
│   ├── manifests.md         # YAML manifest documentation
│   ├── monitoring-alerts.md # Alert configurations and runbooks
│   └── routing.md           # HTTP routing configuration guide
└── README.md           # This file
```

## Configuration

This application uses a dual-configuration approach:

1. **Infrastructure Config** (`/config/parameters-{env}.json`)
   - Azure resource names and IDs
   - Networking configuration
   - Key Vault, ACR, managed identity settings

2. **Application Config** (`config/app-config-{env}.json`)
   - Container resource allocations (CPU, memory)
   - Scaling rules (min/max replicas, concurrent requests)
   - Health probe settings
   - Application environment variables
   - Image tags and naming

See `docs/configuration.md` for detailed configuration documentation.

### Environment-Specific Settings

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| CPU | 0.5 | 1.0 | 2.0 |
| Memory | 1.0Gi | 2.0Gi | 4.0Gi |
| Min Replicas | 0 (scale-to-zero) | 1 | 2 (HA) |
| Max Replicas | 10 | 20 | 50 |
| Image Tag | latest | latest | stable |

To customize settings, edit the appropriate `config/app-config-{env}.json` file.

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

### Option 1: YAML-Based Deployment (Recommended)

The YAML-based approach provides better version control, declarative configuration, and easier GitOps integration.

```bash
cd sample-app

# Deploy to development environment
./scripts/deploy-yaml.sh dev

# Deploy to staging
./scripts/deploy-yaml.sh staging

# Deploy to production
./scripts/deploy-yaml.sh prod
```

**What this does:**
1. Verifies infrastructure exists
2. Builds Docker image
3. Pushes to Azure Container Registry
4. Generates environment-specific YAML manifest from template
5. Creates or updates Container App using `az containerapp create --yaml`

**Benefits:**
- ✅ **Version Control**: YAML manifest can be committed to Git
- ✅ **Declarative**: Full container app configuration in one file
- ✅ **Repeatable**: Same YAML produces consistent deployments
- ✅ **GitOps Ready**: Easy integration with ArgoCD, Flux, etc.
- ✅ **Review-Friendly**: Easier to review changes in PRs
- ✅ **Template Support**: Single template for all environments

**Generated Files:**
- `manifests/containerapp.yaml` - Template with `{{variables}}`
- `manifests/.generated/containerapp-dev.yaml` - Generated manifest for dev
- `manifests/.generated/containerapp-staging.yaml` - Generated for staging
- `manifests/.generated/containerapp-prod.yaml` - Generated for prod

### Option 2: CLI-Based Deployment

Traditional approach using Azure CLI flags:

```bash
cd sample-app

# Deploy to development environment
./scripts/deploy.sh dev

# Deploy to staging
./scripts/deploy.sh staging

# Deploy to staging
./scripts/deploy.sh staging

# Deploy to production
./scripts/deploy.sh prod
```

**What this does:**
1. Verifies infrastructure exists
2. Builds Docker image
3. Pushes to Azure Container Registry
4. Creates or updates Container App using CLI flags

### YAML Manifest Template

The YAML manifest (`manifests/containerapp.yaml`) includes:

**Container Configuration:**
- Image reference with ACR integration
- Resource limits (CPU: 0.5, Memory: 1.0Gi)
- Environment variables (direct and from secrets)
- User-assigned managed identity

**Health Probes:**
- Liveness probe: `/health/live` (restart if fails)
- Readiness probe: `/health/ready` (no traffic if fails)
- Startup probe: `/health` (for slow-starting apps)

**Scaling:**
- Min replicas: 0 (scale to zero)
- Max replicas: Configurable via `parameters.json`
- HTTP-based scaling: 10 concurrent requests
- Optional CPU/Memory-based scaling rules

**Security:**
- Key Vault secret references
- Managed identity for ACR pull
- HTTPS-only ingress
- CORS configuration (optional)

**Example YAML variables:**
```yaml
properties:
  environmentId: /subscriptions/.../managedEnvironments/{{CAE_NAME}}
  configuration:
    ingress:
      external: true
      targetPort: 8000
    registries:
      - server: {{ACR_SERVER}}
        identity: {{UAMI_ID}}
    secrets:
      - name: postgres-connection-string
        keyVaultUrl: https://{{KV_NAME}}.vault.azure.net/secrets/...
        identity: {{UAMI_ID}}
  template:
    containers:
      - name: api
        image: {{IMAGE_NAME}}
        resources:
          cpu: 0.5
          memory: 1.0Gi
    scale:
      minReplicas: 0
      maxReplicas: {{MAX_REPLICAS}}
```

### Viewing Deployed YAML

To see the actual deployed configuration:

```bash
# View current Container App as YAML
az containerapp show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --output yaml > deployed-config.yaml

# View generated manifest
cat manifests/.generated/containerapp-dev.yaml
```

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

### Configure HTTP Routing (Optional)

To route multiple container apps via a single environment FQDN:

```bash
cd sample-app

# Deploy routing configuration
./scripts/deploy-routing.sh dev
```

This enables path-based routing:
- `https://{env-fqdn}/app1` → This container app
- `https://{env-fqdn}/app2` → Another container app (when deployed)

See [docs/routing.md](docs/routing.md) for routing configuration and multi-app deployment.

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

## Documentation

- **[Configuration Guide](docs/configuration.md)** - Environment-specific app configuration
- **[Deployment Guide](docs/deployment.md)** - Quick deployment reference
- **[YAML Manifests](docs/manifests.md)** - Container App manifest documentation
- **[HTTP Routing](docs/routing.md)** - Environment-level URL routing setup
- **[Monitoring & Alerts](docs/monitoring-alerts.md)** - Alert configurations and runbooks

For infrastructure-level documentation:
- **[SSL/TLS Setup](../docs/ssl-tls-setup.md)** - Custom domain and SSL certificate configuration (infrastructure)

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
