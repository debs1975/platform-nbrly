# HTTP Routing in Container Apps Environment

This document explains how to configure rule-based HTTP routing to route traffic to multiple container apps using a single environment-level FQDN.

## Overview

Azure Container Apps Environment supports HTTP routing rules that allow you to:
- Route requests to different container apps based on URL path prefixes
- Use a single entry point (environment FQDN) for multiple microservices
- Implement path-based routing without additional load balancers
- Rewrite URL paths before forwarding to target apps

## Architecture

```
Client Request
    ↓
Environment FQDN (https://env.region.azurecontainerapps.io)
    ↓
HTTP Route Config (routing rules)
    ↓
├─ /app1/* → Container App 1 (api-ca)  - Basic FastAPI
└─ /app2/* → Container App 2 (api2-ca) - Task Management API
```

## Configuration Files

### Routing Template
**Location:** `manifests/routing.yaml`

Defines routing rules with variable placeholders:

```yaml
routes:
  - match:
      prefix: /app1
    action:
      prefixRewrite: /app1
    target:
      containerApp: {{PROJECT_NAME}}-{{ENV}}-eastus-api-ca
  
  - match:
      prefix: /app2
    action:
      prefixRewrite: /app2
    target:
      containerApp: {{PROJECT_NAME}}-{{ENV}}-eastus-api2-ca
```

### Deployment Script
**Location:** `scripts/deploy-routing.sh`

Generates environment-specific routing config and applies it to the Container Apps Environment.

## Routing Rules

### Route Structure

Each route consists of:

1. **match**: Defines the URL pattern to match
   - `prefix`: URL path prefix (e.g., `/app1`, `/api`)

2. **action**: Defines how to transform the request
   - `prefixRewrite`: Rewrites the path prefix before forwarding
     - `/app1` → Keep `/app1` prefix (app handles it)
     - `/` → Remove prefix (app gets clean path)

3. **target**: Defines where to route the request
   - `containerApp`: Name of the target container app

### Example Routes

```yaml
# Route with prefix preservation
- match:
    prefix: /app1
  action:
    prefixRewrite: /app1  # App receives /app1/health
  target:
    containerApp: myapp-dev-eastus-api-ca

# Route with prefix removal
- match:
    prefix: /api
  action:
    prefixRewrite: /  # App receives /health (prefix removed)
  target:
    containerApp: myapp-dev-eastus-backend-ca

# Default route (root)
- match:
    prefix: /
  action:
    prefixRewrite: /
  target:
    containerApp: myapp-dev-eastus-web-ca
```

## Application Configuration

### FastAPI with Root Path

When using prefix preservation (`prefixRewrite: /app1`), configure your FastAPI app:

```python
app = FastAPI(
    title="My API",
    root_path="/app1"  # Tells FastAPI it's mounted at /app1
)
```

This ensures:
- OpenAPI docs available at `/app1/docs`
- Routes properly resolve (e.g., `/app1/health`)
- URL generation works correctly

### FastAPI without Root Path

When using prefix removal (`prefixRewrite: /`), use default FastAPI:

```python
app = FastAPI(
    title="My API"
    # No root_path needed
)
```

## Deployment

### 1. Deploy Container Apps

First, deploy both container apps that will be part of the routing:

```bash
cd sample-app

# Build and deploy App1
./scripts/deploy.sh dev latest app

# Build and deploy App2
./scripts/deploy.sh dev latest app2
```

### 2. Configure Routing Rules

Edit `manifests/routing.yaml` to define your routes (already configured for App1 and App2):

```yaml
routes:
  - match:
      prefix: /app1
    action:
      prefixRewrite: /app1
    target:
      containerApp: {{PROJECT_NAME}}-{{ENV}}-eastus-api-ca
  
  - match:
      prefix: /app2
    action:
      prefixRewrite: /app2
    target:
      containerApp: {{PROJECT_NAME}}-{{ENV}}-eastus-api2-ca
```

**Note:** Container App names updated to comply with Azure's 32-character limit:
- App1: `nbrly-dev-eastus-api-ca` (22 chars)
- App2: `nbrly-dev-eastus-api2-ca` (23 chars)

### 3. Deploy Routing Configuration

```bash
cd sample-app

# Deploy routing to dev environment
./scripts/deploy-routing.sh dev

# Deploy to other environments
./scripts/deploy-routing.sh staging
./scripts/deploy-routing.sh prod
```

### 4. Test Routes

```bash
# Get environment FQDN
ENV_FQDN=$(az containerapp env show \
  --name nbrly-dev-eastus-cae \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.defaultDomain -o tsv)

# Test App1 routes
curl https://${ENV_FQDN}/app1/health
curl https://${ENV_FQDN}/app1/api/info
curl https://${ENV_FQDN}/app1/docs

# Test App2 routes
curl https://${ENV_FQDN}/app2/health
curl https://${ENV_FQDN}/app2/api/tasks
curl https://${ENV_FQDN}/app2/docs
```

## Managing Routes

### View Current Routes

```bash
az containerapp env http-route-config show \
  --http-route-config-name myapp-dev-eastus-route \
  --resource-group myapp-dev-eastus-rg \
  --name myapp-dev-eastus-env
```

### Update Routes

Modify `manifests/routing.yaml` and redeploy:

```bash
./scripts/deploy-routing.sh dev
```

### Delete Routes

```bash
az containerapp env http-route-config delete \
  --http-route-config-name myapp-dev-eastus-route \
  --resource-group myapp-dev-eastus-rg \
  --name myapp-dev-eastus-env
```

## Ingress Configuration

### External Ingress (Default)

Container apps with external ingress can receive:
- Direct traffic via their individual FQDNs
- Routed traffic via environment FQDN + path prefix

### Internal Ingress

Container apps with internal ingress can only receive:
- Routed traffic via environment FQDN + path prefix
- Traffic from other apps in the environment

To use internal ingress, modify `manifests/containerapp.yaml`:

```yaml
properties:
  configuration:
    ingress:
      external: false  # Internal only
      targetPort: {{CONTAINER_PORT}}
```

## Best Practices

### 1. Route Ordering

Routes are evaluated in order. Place more specific routes first:

```yaml
routes:
  # Specific route first
  - match:
      prefix: /api/admin
    target:
      containerApp: admin-api-ca
  
  # General route second
  - match:
      prefix: /api
    target:
      containerApp: public-api-ca
```

### 2. Prefix Rewriting

**Use prefix preservation** when:
- App needs to know its mount point
- Multiple versions of same app (`/v1`, `/v2`)
- App generates URLs that need the prefix

**Use prefix removal** when:
- App is designed as standalone service
- Simpler app configuration
- App doesn't care about routing context

### 3. Health Probes

Health probes bypass routing and go directly to container apps. Configure them on individual apps, not via routing.

### 4. TLS/HTTPS

- Environment FQDN provides automatic TLS
- All routed traffic is HTTPS
- Individual container app FQDNs also have TLS

### 5. Environment Separation

Use separate routing configs per environment:

```bash
manifests/.generated/
├── routing-dev.yaml
├── routing-staging.yaml
└── routing-prod.yaml
```

## Troubleshooting

### Route not working

1. **Verify route exists:**
   ```bash
   az containerapp env http-route-config show \
     --http-route-config-name <route-name> \
     --resource-group <rg> \
     --name <env-name>
   ```

2. **Check target app exists:**
   ```bash
   az containerapp show \
     --name <app-name> \
     --resource-group <rg>
   ```

3. **Test app directly:**
   ```bash
   # Get app FQDN
   APP_FQDN=$(az containerapp show \
     --name <app-name> \
     --resource-group <rg> \
     --query properties.configuration.ingress.fqdn -o tsv)
   
   # Test direct access (include app's root path prefix)
   curl https://${APP_FQDN}/app1/health
   ```

### 404 Not Found

- Check `prefixRewrite` matches app's expected paths
- Verify `root_path` in FastAPI matches routing config
- Ensure app is listening on correct port

### 503 Service Unavailable

- Container app may be scaled to zero
- Health probes may be failing
- App may not be ready to receive traffic

## Security Considerations

### Network Security

- Use internal ingress for apps that should only be accessed via routing
- Apply NSG rules to restrict environment-level ingress
- Consider Private Link for fully private environments

### Authentication

- Implement authentication at environment level (future feature)
- Each container app can have its own authentication
- Consider Azure Front Door or API Management for advanced auth

### Rate Limiting

- Configure rate limiting on individual container apps
- Consider Azure Front Door or API Management for global rate limiting

## Examples

### Microservices Architecture

```yaml
routes:
  # Frontend
  - match:
      prefix: /
    action:
      prefixRewrite: /
    target:
      containerApp: myapp-web-ca
  
  # User API
  - match:
      prefix: /api/users
    action:
      prefixRewrite: /
    target:
      containerApp: myapp-users-api-ca
  
  # Orders API
  - match:
      prefix: /api/orders
    action:
      prefixRewrite: /
    target:
      containerApp: myapp-orders-api-ca
  
  # Admin
  - match:
      prefix: /admin
    action:
      prefixRewrite: /
    target:
      containerApp: myapp-admin-ca
```

### API Versioning

```yaml
routes:
  # API v2 (newer)
  - match:
      prefix: /api/v2
    action:
      prefixRewrite: /
    target:
      containerApp: myapp-api-v2-ca
  
  # API v1 (legacy)
  - match:
      prefix: /api/v1
    action:
      prefixRewrite: /
    target:
      containerApp: myapp-api-v1-ca
  
  # Default to v2
  - match:
      prefix: /api
    action:
      prefixRewrite: /
    target:
      containerApp: myapp-api-v2-ca
```

## Related Documentation

- [Container Apps Documentation](deployment.md)
- [YAML Manifests](manifests.md)
- [Configuration Guide](configuration.md)
- [Azure Container Apps Routing](https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing)

## Reference

### Azure CLI Commands

```bash
# Create route config
az containerapp env http-route-config create \
  --http-route-config-name <name> \
  --resource-group <rg> \
  --name <env-name> \
  --yaml <routing.yaml>

# Update route config
az containerapp env http-route-config update \
  --http-route-config-name <name> \
  --resource-group <rg> \
  --name <env-name> \
  --yaml <routing.yaml>

# Show route config
az containerapp env http-route-config show \
  --http-route-config-name <name> \
  --resource-group <rg> \
  --name <env-name>

# Delete route config
az containerapp env http-route-config delete \
  --http-route-config-name <name> \
  --resource-group <rg> \
  --name <env-name>
```

### Routing YAML Schema

```yaml
routes:
  - match:
      prefix: string      # URL path prefix to match
    action:
      prefixRewrite: string  # Rewrite prefix before forwarding
    target:
      containerApp: string   # Target container app name
```
