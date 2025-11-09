# Sample FastAPI Application

This directory contains sample FastAPI applications demonstrating deployment to Azure Container Apps with support for **multiple independent applications using separate container images**.

## Features

- ✅ FastAPI web framework
- ✅ **Multi-application support** (app1 and app2 as separate images)
- ✅ Health check endpoints (health, readiness, liveness)
- ✅ Key Vault secret integration
- ✅ Environment variable configuration
- ✅ Multi-stage Docker build for optimization
- ✅ Non-root container user for security
- ✅ Automatic deployment script
- ✅ Independent scaling per application

## Application Structure

```
sample-app/
├── main_app1.py         # FastAPI application (App1 - Basic API)
├── main_app2.py         # FastAPI application (App2 - Task Management)
├── requirements.txt     # Python dependencies
├── Dockerfile.app1     # Multi-stage Docker build for App1
├── Dockerfile.app2     # Multi-stage Docker build for App2
├── Dockerfile          # Legacy (use Dockerfile.app1 or Dockerfile.app2)
├── .dockerignore       # Docker build exclusions
├── .gitignore          # Git exclusions
├── config/
│   ├── app-config-dev.json      # App1 dev environment config
│   ├── app-config-staging.json  # App1 staging environment config
│   ├── app-config-prod.json     # App1 production environment config
│   ├── app2-config-dev.json     # App2 dev environment config
│   ├── app2-config-staging.json # App2 staging environment config
│   ├── app2-config-prod.json    # App2 production environment config
│   └── README.md               # Configuration documentation
├── manifests/
│   ├── containerapp.yaml    # Container App YAML manifest template
│   ├── routing.yaml         # HTTP routing configuration template
│   └── .generated/          # Generated manifests (gitignored)
├── scripts/
│   ├── build-push.sh        # Docker build and push to ACR
│   ├── deploy-app.sh        # Container App deployment (supports app/app2)
│   ├── deploy.sh            # Complete deployment wrapper (build + deploy)
│   ├── deploy-yaml.sh       # YAML-based deployment script (recommended)
│   ├── deploy-routing.sh    # HTTP routing deployment script
│   └── setup-monitoring.sh  # Monitoring & alerts configuration
├── docs/
│   ├── configuration.md     # Configuration documentation
│   ├── deployment.md        # Quick deployment reference
│   ├── manifests.md         # YAML manifest documentation
│   ├── monitoring-alerts.md # Alert configurations and runbooks
│   └── routing.md           # HTTP routing configuration guide
├── MULTI_APP_GUIDE.md  # **Multi-application deployment guide**
└── README.md           # This file
```

## Multi-Application Architecture

This repository demonstrates deploying **multiple independent applications** as **separate Docker images**:

- **App1** (`main_app1.py`): Basic FastAPI with demo endpoints at `/app1/*`
  - Built from `Dockerfile.app1`
  - Image: `sample-api-app1:tag`
  - Port: 8000

- **App2** (`main_app2.py`): Task Management API with CRUD operations at `/app2/*`
  - Built from `Dockerfile.app2`
  - Image: `sample-api-app2:tag`
  - Port: 8001

Each app has its own:
- Dedicated Docker image (smaller, app-specific)
- Separate Dockerfile
- Independent build and deployment process
- Distinct Container App with its own resources
- Custom scaling configuration
- App-specific health probe paths

**Benefits of Separate Images:**
- ✅ Smaller image sizes (each contains only one app)
- ✅ True separation and isolation
- ✅ Independent build and release cycles
- ✅ No runtime environment variable dependency
- ✅ Clearer deployment model

📘 **See [MULTI_APP_GUIDE.md](./MULTI_APP_GUIDE.md) for complete multi-app deployment patterns and examples.**

## Configuration

Two types of configuration files:

1. **Infrastructure Config** (`/iac-cli/config/parameters-{env}.json`)
   - Contains infrastructure-level settings shared across all apps
   - ACR name, Container Apps Environment, Key Vault, etc.
   - Managed by infrastructure team

2. **Application Config** (`/sample-app/config/app-config-{env}.json`)
   - Application-specific settings
   - Container resources (CPU, memory), scaling rules, health probes
   - Managed by application team

See `docs/configuration.md` for detailed configuration documentation.

### Environment-Specific Settings (App1)

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| CPU | 0.5 | 1.0 | 2.0 |
| Memory | 1.0Gi | 2.0Gi | 4.0Gi |
| Min Replicas | 0 (scale-to-zero) | 1 | 2 (HA) |
| Max Replicas | 10 | 20 | 50 |
| Image Tag | latest | latest | stable |
| Port | 8000 | 8000 | 8000 |
| Root Path | /app1 | /app1 | /app1 |

### Environment-Specific Settings (App2)

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| CPU | 0.5 | 1.0 | 2.0 |
| Memory | 1.0Gi | 2.0Gi | 4.0Gi |
| Min Replicas | 0 (scale-to-zero) | 1 | 2 (HA) |
| Max Replicas | 10 | 20 | 50 |
| Image Tag | latest | latest | stable |
| Port | 8001 | 8001 | 8001 |
| Root Path | /app2 | /app2 | /app2 |

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

### Run App1 locally with Python

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

# Run App1
uvicorn main_app1:app --host 0.0.0.0 --port 8000 --reload
```

Visit: `http://localhost:8000/app1/`

### Run App2 locally with Python

```bash
cd sample-app

# Use same virtual environment
source venv/bin/activate

# Run App2 on different port
export PORT=8001
uvicorn main_app2:app --host 0.0.0.0 --port 8001 --reload
```

Visit: `http://localhost:8001/app2/`

Access at: http://localhost:8000

### Run App1 locally with Docker

```bash
cd sample-app

# Build App1 image
docker build -f Dockerfile.app1 -t sample-api-app1:latest .

# Run App1
docker run -p 8000:8000 \
  -e ENVIRONMENT=development \
  -e ALLOWED_ORIGINS="*" \
  sample-api-app1:latest
```

Access at: `http://localhost:8000/app1/`

### Run App2 locally with Docker

```bash
cd sample-app

# Build App2 image
docker build -f Dockerfile.app2 -t sample-api-app2:latest .

# Run App2
docker run -p 8001:8001 \
  -e ENVIRONMENT=development \
  -e ALLOWED_ORIGINS="*" \
  sample-api-app2:latest
```

Access at: `http://localhost:8001/app2/`

## Deployment to Azure

### Quick Start: Complete Deployment

Deploy everything (build, push, and deploy) in one command:

```bash
cd sample-app

# Deploy App1 to development
./scripts/deploy.sh dev latest app

# Deploy App2 to development
./scripts/deploy.sh dev latest app2

# Deploy both apps to staging  
./scripts/deploy.sh staging latest app
./scripts/deploy.sh staging latest app2

# Deploy to production with custom tag
./scripts/deploy.sh prod v1.2.3 app
./scripts/deploy.sh prod v1.2.3 app2
```

### Modular Deployment Workflows

For more control, use separate scripts for each step:

#### 1. Build and Push Images (Separate for Each App)

```bash
# Build and push App1 image
./scripts/build-push.sh dev latest app

# Build and push App2 image
./scripts/build-push.sh dev latest app2

# Build with custom tags
./scripts/build-push.sh prod v1.2.3 app
./scripts/build-push.sh prod v1.2.3 app2
```

**What this does:**
- ✅ Builds Docker image using **Dockerfile.app1** or **Dockerfile.app2**
- ✅ Creates separate images: **sample-api-app1** and **sample-api-app2**
- ✅ Tags with environment-specific tag (or custom tag)
- ✅ Pushes to Azure Container Registry
- ✅ Verifies image exists in ACR
- ✅ Shows available tags

#### 2. Deploy Container Apps Independently

```bash
# Deploy App1 using its dedicated image
./scripts/deploy-app.sh dev latest app

# Deploy App2 using its dedicated image
./scripts/deploy-app.sh dev latest app2

# Deploy specific image tags to production
./scripts/deploy-app.sh prod v1.2.3 app
./scripts/deploy-app.sh prod v1.2.3 app2
```

**What this does:**
- ✅ Verifies infrastructure exists
- ✅ Verifies app-specific image exists in ACR (sample-api-app1 or sample-api-app2)
- ✅ Creates or updates Container App
- ✅ Applies app-specific configuration (resources, scaling, health probes)
- ✅ Uses dedicated image per app (no APP_MODULE needed)
- ✅ Shows application URL and test endpoints

**Use Cases:**
- **Independent Releases**: Deploy App1 and App2 on different schedules
- **Rollback**: Deploy a previous image tag to specific app
- **Testing**: Deploy and test each app separately
- **Independent Scaling**: Scale App1 and App2 based on their own traffic

### Option 3: YAML-Based Deployment

The YAML-based approach provides declarative configuration and GitOps integration:

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
1. Builds and pushes Docker image
2. Generates environment-specific YAML manifest from template
3. Creates or updates Container App using `az containerapp create --yaml`

**Benefits:**
- ✅ **Version Control**: YAML manifest can be committed to Git
- ✅ **Declarative**: Full container app configuration in one file
- ✅ **Repeatable**: Same YAML produces consistent deployments
- ✅ **GitOps Ready**: Easy integration with ArgoCD, Flux, etc.

**Generated Files:**
- `manifests/containerapp.yaml` - Template with `{{variables}}`
- `manifests/.generated/containerapp-{env}.yaml` - Environment-specific manifests

### Deployment Comparison

| Aspect | deploy.sh | build-push.sh + deploy-app.sh | deploy-yaml.sh |
|--------|-----------|-------------------------------|----------------|
| **Build Image** | ✅ | ✅ (separate step) | ✅ |
| **Push to ACR** | ✅ | ✅ (separate step) | ✅ |
| **Deploy App** | ✅ | ✅ (separate step) | ✅ |
| **Custom Tags** | ✅ | ✅ | ❌ |
| **Modular** | ❌ | ✅✅ | ❌ |
| **GitOps** | ❌ | ❌ | ✅✅ |
| **CI/CD Friendly** | ✅ | ✅✅ | ✅ |

### Container App Configuration

**Container Configuration:**
- Separate images per app with ACR integration
  - App1: `sample-api-app1:tag` (from Dockerfile.app1)
  - App2: `sample-api-app2:tag` (from Dockerfile.app2)
- Resource limits (CPU: 0.5-2.0, Memory: 1.0-4.0Gi per environment)
- Environment variables (direct and from secrets)
- Each image hardcodes its app in CMD (no APP_MODULE needed)
- User-assigned managed identity for ACR pull and Key Vault access

**Health Probes (App-Specific):**

App1:
- Liveness: `/app1/health/live`
- Readiness: `/app1/health/ready`
- Startup: `/app1/health`

App2:
- Liveness: `/app2/health/live`
- Readiness: `/app2/health/ready`
- Startup: `/app2/health`

**Scaling:**
- Min replicas: 0 (scale to zero in dev)
- Max replicas: Environment-specific (10/20/50)
- HTTP-based scaling: 10 concurrent requests
- Optional CPU/Memory-based scaling rules
- **Independent scaling** per app

**Security:**
- Key Vault secret references
- Managed identity for ACR pull
- HTTPS-only ingress
- CORS configuration (optional)

**Example YAML variables (App1):**
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
        image: {{ACR_NAME}}.azurecr.io/sample-api-app1:{{TAG}}
        env:
          - name: PORT
            value: "8000"
          - name: LOG_LEVEL
            value: "INFO"
        resources:
          cpu: 0.5
          memory: 1.0Gi
    scale:
      minReplicas: 0
      maxReplicas: {{MAX_REPLICAS}}
```

**Example YAML variables (App2):**
```yaml
# Same structure as App1, but with:
# - Different image: sample-api-app2:{{TAG}}
# - targetPort: 8001
# - PORT: "8001"
# - Different health probe paths (/app2/*)
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

After deploying applications, set up monitoring:

```bash
cd sample-app

# Configure Application Insights and alerts for App1
./scripts/setup-monitoring.sh dev app

# Configure Application Insights and alerts for App2
./scripts/setup-monitoring.sh dev app2
```

This creates:
- Application Insights integration
- High restart count alert
- High CPU/memory usage alerts
- HTTP latency and error rate alerts
- Scale-to-zero monitoring

See [docs/monitoring-alerts.md](docs/monitoring-alerts.md) for alert details and investigation runbooks.

### Configure HTTP Routing (Multi-App Support)

To route both apps via a single environment FQDN:

```bash
cd sample-app

# Deploy routing configuration
./scripts/deploy-routing.sh dev
```

This enables path-based routing:
- `https://{env-fqdn}/app1/*` → App1 (basic API)
- `https://{env-fqdn}/app2/*` → App2 (task management)

See [docs/routing.md](docs/routing.md) for routing configuration.

### Manual Deployment Steps

If you prefer manual deployment:

```bash
# 1. Set variables
PROJECT_NAME="nbrly"
ENV="dev"
ACR_NAME="${PROJECT_NAME}${ENV}eastusacr"
RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"
CAE_NAME="${PROJECT_NAME}-${ENV}-eastus-cae"

# App1 variables
APP1_NAME="${PROJECT_NAME}-${ENV}-eastus-api-ca"
APP1_IMAGE="${ACR_NAME}.azurecr.io/sample-api-app1:latest"

# App2 variables
APP2_NAME="${PROJECT_NAME}-${ENV}-eastus-api-v2-ca"
APP2_IMAGE="${ACR_NAME}.azurecr.io/sample-api-app2:latest"

# 2. Build and push App1 image
az acr login --name $ACR_NAME
docker build -f Dockerfile.app1 -t $APP1_IMAGE .
docker push $APP1_IMAGE

# 3. Build and push App2 image
docker build -f Dockerfile.app2 -t $APP2_IMAGE .
docker push $APP2_IMAGE

# 4. Create Container App for App1
az containerapp create \
  --resource-group $RG_NAME \
  --name $APP1_NAME \
  --environment $CAE_NAME \
  --image $APP1_IMAGE \
  --target-port 8000 \
  --ingress external \
  --cpu 0.5 \
  --memory 1.0Gi \
  --min-replicas 0 \
  --max-replicas 5 \
  --env-vars PORT="8000" LOG_LEVEL="INFO"

# 5. Create Container App for App2
az containerapp create \
  --resource-group $RG_NAME \
  --name $APP2_NAME \
  --environment $CAE_NAME \
  --image $APP2_IMAGE \
  --target-port 8001 \
  --ingress external \
  --cpu 0.5 \
  --memory 1.0Gi \
  --min-replicas 0 \
  --max-replicas 5 \
  --env-vars PORT="8001" LOG_LEVEL="INFO"
```

## API Endpoints

### App1 (Basic API)

Once deployed, App1 provides these endpoints at `/app1/*`:

- `GET /app1/` - Root endpoint with welcome message
- `GET /app1/info` - Application information
- `GET /app1/health` - Basic health check
- `GET /app1/health/live` - Liveness probe
- `GET /app1/health/ready` - Readiness probe
- `GET /app1/demo/items/{item_id}` - Demo item lookup
- `GET /app1/demo/secret` - Key Vault secret demo

### App2 (Task Management API)

Once deployed, App2 provides these endpoints at `/app2/*`:

**Health Checks:**
- `GET /app2/` - Root endpoint
- `GET /app2/health` - Basic health check
- `GET /app2/health/live` - Liveness probe
- `GET /app2/health/ready` - Readiness probe

**Task Management:**
- `GET /app2/api/tasks` - List all tasks
- `POST /app2/api/tasks` - Create new task
- `GET /app2/api/tasks/{task_id}` - Get specific task
- `PUT /app2/api/tasks/{task_id}` - Update task
- `DELETE /app2/api/tasks/{task_id}` - Delete task

**Example Usage:**
```bash
# Get App2 URL
APP2_URL=$(az containerapp show \
  --name nbrly-dev-eastus-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.configuration.ingress.fqdn \
  -o tsv)

# Create a task
curl -X POST "https://${APP2_URL}/app2/api/tasks" \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy to production","description":"Deploy v1.2.3","completed":false}'

# List all tasks
curl "https://${APP2_URL}/app2/api/tasks"

# Update a task
curl -X PUT "https://${APP2_URL}/app2/api/tasks/1" \
  -H "Content-Type: application/json" \
  -d '{"completed":true}'
```

### App1 (Basic API)

### Health Checks

- `GET /app1/health` - Basic health check
- `GET /app1/health/ready` - Readiness probe (checks dependencies)
- `GET /app1/health/live` - Liveness probe (simple alive check)

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

### View Logs (App1)

```bash
# Live logs for App1
az containerapp logs show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# Historical logs via Log Analytics
az monitor log-analytics query \
  --workspace nbrly-dev-eastus-law \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'nbrly-dev-eastus-api-ca' | order by TimeGenerated desc | take 100"
```

### View Logs (App2)

```bash
# Live logs for App2
az containerapp logs show \
  --name nbrly-dev-eastus-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# Historical logs via Log Analytics
az monitor log-analytics query \
  --workspace nbrly-dev-eastus-law \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'nbrly-dev-eastus-api-v2-ca' | order by TimeGenerated desc | take 100"
```

### View Metrics

Access metrics in Azure Portal:
- Resource Group → Container App (App1 or App2) → Metrics
- View: Requests, CPU, Memory, Replicas

Or via CLI:
```bash
# App1 metrics
az monitor metrics list \
  --resource nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --resource-type "Microsoft.App/containerApps" \
  --metric "Requests"

# App2 metrics
az monitor metrics list \
  --resource nbrly-dev-eastus-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --resource-type "Microsoft.App/containerApps" \
  --metric "Requests"
```

### Application Insights

Both Container Apps are configured with Application Insights for:
- Request tracking
- Dependency tracking
- Exception tracking
- Custom telemetry

Each app appears as a separate component in Application Insights with distinct operation names based on their root paths (`/app1/*` and `/app2/*`).

## Scaling Configuration

Both Container Apps are configured for auto-scaling with environment-specific settings:

**Development:**
```
Min Replicas: 0 (scale to zero when idle)
Max Replicas: 10
Scaling Rules:
  - HTTP requests: Scale at 10 concurrent requests
```

**Production:**
```
Min Replicas: 2 (high availability)
Max Replicas: 50
Scaling Rules:
  - HTTP requests: Scale at 10 concurrent requests
  - CPU: Scale at 70% utilization (optional)
```

Each app scales **independently** based on its own traffic and resource usage.

## Troubleshooting

### App1 won't start

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

# Check logs
az containerapp logs show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --tail 50
```

### App2 won't start

```bash
# Check provisioning state
az containerapp show \
  --name nbrly-dev-eastus-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.provisioningState

# Verify correct image is deployed
az containerapp show \
  --name nbrly-dev-eastus-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.template.containers[0].image -o tsv

# Expected: nbrlydeveastusacr.azurecr.io/sample-api-app2:latest

# Check logs
az containerapp logs show \
  --name nbrly-dev-eastus-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --tail 50
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

Update `main_app1.py` to add actual database connection logic in `/api/database/test`.

### Add More Endpoints

Add new routes in `main_app1.py`:
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

**App1:**
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

**App2:**
```bash
# Stream live logs
az containerapp logs show \
  --name nbrly-dev-eastus-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# View recent logs
az containerapp logs show \
  --name nbrly-dev-eastus-api-v2-ca \
  --resource-group nbrly-dev-eastus-rg \
  --tail 100
```

### Check Alert Status
```bash
# List all Container App alerts
az monitor metrics alert list \
  --resource-group nbrly-dev-eastus-rg \
  --query "[?contains(name, 'api-ca') || contains(name, 'api-v2-ca')]" \
  --output table

# View alert history
az monitor activity-log list \
  --resource-group nbrly-dev-eastus-rg \
  --query "[?contains(category.value, 'Alert')]" \
  --output table
```

For detailed monitoring documentation, see [docs/monitoring-alerts.md](docs/monitoring-alerts.md).

## Documentation

- **[Multi-App Deployment Guide](MULTI_APP_GUIDE.md)** - Complete guide for deploying multiple apps from single image
- **[Configuration Guide](docs/configuration.md)** - Environment-specific app configuration
- **[Deployment Guide](docs/deployment.md)** - Quick deployment reference
- **[YAML Manifests](docs/manifests.md)** - Container App manifest documentation
- **[HTTP Routing](docs/routing.md)** - Environment-level URL routing setup
- **[Monitoring & Alerts](docs/monitoring-alerts.md)** - Alert configurations and runbooks

For infrastructure-level documentation:
- **[SSL/TLS Setup](../iac-cli/docs/ssl-tls-setup.md)** - Custom domain and SSL certificate configuration (infrastructure)

## Next Steps

1. ✅ Deploy infrastructure (iac-cli/scripts/01-05)
2. ✅ Build App1 Docker image (`./scripts/build-push.sh dev latest app`)
3. ✅ Build App2 Docker image (`./scripts/build-push.sh dev latest app2`)
4. ✅ Deploy App1 (`./scripts/deploy-app.sh dev latest app`)
5. ✅ Deploy App2 (`./scripts/deploy-app.sh dev latest app2`)
6. 🔄 Configure monitoring (`./scripts/setup-monitoring.sh dev`)
7. 🔄 Configure HTTP routing (`./scripts/deploy-routing.sh dev`)
8. 🔄 Customize application logic for your use case
9. 🔄 Add database connectivity (PostgreSQL/Cosmos DB)
10. 🔄 Implement authentication (Azure AD/OAuth)
11. 🔄 Add CI/CD pipeline (GitHub Actions/Azure DevOps)
12. 🔄 Deploy to staging/production environments

## Architecture Benefits

This multi-app architecture with separate images provides:
- ✅ **True Separation**: Each app has its own dedicated Docker image
- ✅ **Smaller Images**: Images contain only the code they need
- ✅ **Independent Scaling**: Each app scales based on its own traffic
- ✅ **Resource Isolation**: Separate CPU/memory allocation per app
- ✅ **Independent Releases**: Deploy App1 and App2 on different schedules
- ✅ **Clear Deployment Model**: No runtime env var selection needed
- ✅ **Cost Optimization**: Scale-to-zero when idle, pay only for usage
- ✅ **Easy Rollback**: Deploy previous image tags for specific apps

## Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Container Apps Multi-Container Guide](https://learn.microsoft.com/en-us/azure/container-apps/containers)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Uvicorn Documentation](https://www.uvicorn.org/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
