# Configuration Files

This directory contains environment-specific configuration files for deploying multi-tenant FastAPI applications with Azure Container Apps and Application Gateway.

## Directory Structure

```
config/
├── README.md                      # This file
├── parameters-dev.json           # Global infrastructure parameters (dev)
├── parameters-staging.json       # Global infrastructure parameters (staging) [Future]
├── parameters-prod.json          # Global infrastructure parameters (prod) [Future]
├── nbrly/
│   ├── parameters-dev.json      # NBRLY tenant configuration (dev)
│   ├── parameters-staging.json  # NBRLY tenant configuration (staging) [Future]
│   └── parameters-prod.json     # NBRLY tenant configuration (prod) [Future]
└── bloom/
    ├── parameters-dev.json      # BLOOM tenant configuration (dev)
    ├── parameters-staging.json  # BLOOM tenant configuration (staging) [Future]
    └── parameters-prod.json     # BLOOM tenant configuration (prod) [Future]
```

## Configuration Files

### Global Configuration (`parameters-dev.json`)

Contains infrastructure-wide settings shared across all tenants:

```json
{
  "env": "dev",
  "region": "eastus",
  "project": "astra",
  "resourceGroup": "rg-astrapia-dev",
  "containerRegistry": "astradevacr",
  "vnetAddressPrefix": "10.100.0.0/16",
  "appGatewaySubnetPrefix": "10.100.0.0/24",
  "customDomain": {
    "tenantDomains": {
      "nbrly": "nbrly-dev.astrapia.io",
      "bloom": "bloom-dev.astrapia.io"
    }
  },
  "applicationGateway": {
    "name": "agw-astrapia-dev",
    "sku": "WAF_v2"
  },
  "containerApps": {
    "defaults": {
      "cpu": 0.5,
      "memory": "1.0Gi",
      "minReplicas": 1,
      "maxReplicas": 3
    }
  }
}
```

**Key Sections:**
- **Environment**: Environment name, region, project identification
- **Networking**: VNet and subnet configurations
- **Custom Domain**: SSL certificates and tenant domain mappings
- **Application Gateway**: SKU, capacity, WAF settings
- **Container Apps**: Default resource limits and scaling settings
- **Logging**: Log Analytics and Application Insights configuration
- **Tags**: Azure resource tags for governance

### Tenant Configuration (`nbrly/parameters-dev.json`, `bloom/parameters-dev.json`)

Contains tenant-specific settings for each application:

```json
{
  "tenantName": "nbrly",
  "domainName": "nbrly-dev.astrapia.io",
  "containerAppEnvironment": "cae-nbrly-dev",
  "applications": {
    "nbapp1": {
      "name": "ca-nbrly-nbapp1-dev",
      "image": "astradevacr.azurecr.io/nbrly/nbapp1",
      "port": 8000,
      "rootPath": "/app1",
      "cpu": 0.5,
      "memory": "1.0Gi",
      "env": {
        "APP_NAME": "nbapp1",
        "ROOT_PATH": "/app1"
      }
    }
  },
  "routing": {
    "backendPools": {
      "app1": "pool-nbrly-app1"
    },
    "priority": 100
  }
}
```

**Key Sections:**
- **Tenant Info**: Tenant name, display name, domain
- **Applications**: Per-application settings (image, resources, environment variables)
- **Routing**: Application Gateway backend pools, HTTP settings, rules
- **Monitoring**: Application Insights and Log Analytics settings
- **Tags**: Tenant-specific resource tags

## Usage in Scripts

### Build Scripts

Build scripts use configuration to determine image names and tags:

```bash
# scripts/build-push/build-push-nbrly.sh
CONFIG_FILE="../config/nbrly/parameters-dev.json"

# Read configuration
TENANT_NAME=$(jq -r '.tenantName' "$CONFIG_FILE")
APP1_IMAGE=$(jq -r '.applications.nbapp1.image' "$CONFIG_FILE")
APP1_TAG=$(jq -r '.applications.nbapp1.tag' "$CONFIG_FILE")

# Build and push
docker build -t "$APP1_IMAGE:$APP1_TAG" ./nbrly/nbapp1/
docker push "$APP1_IMAGE:$APP1_TAG"
```

### Deployment Scripts

Deployment scripts use configuration for Container Apps and environment variables:

```bash
# scripts/deploy/deploy-nbrly.sh
CONFIG_FILE="../config/nbrly/parameters-dev.json"
GLOBAL_CONFIG="../config/parameters-dev.json"

# Read configuration
CAE_NAME=$(jq -r '.containerAppEnvironment' "$CONFIG_FILE")
RESOURCE_GROUP=$(jq -r '.resourceGroup' "$GLOBAL_CONFIG")
APP_NAME=$(jq -r '.applications.nbapp1.name' "$CONFIG_FILE")
IMAGE=$(jq -r '.applications.nbapp1.image' "$CONFIG_FILE")
TAG=$(jq -r '.applications.nbapp1.tag' "$CONFIG_FILE")

# Deploy Container App
az containerapp create \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$CAE_NAME" \
  --image "$IMAGE:$TAG"
```

### Routing Scripts

Routing scripts use configuration for Application Gateway setup:

```bash
# scripts/routing/configure-routing-nbrly.sh
CONFIG_FILE="../config/nbrly/parameters-dev.json"
GLOBAL_CONFIG="../config/parameters-dev.json"

# Read configuration
AGW_NAME=$(jq -r '.applicationGateway.name' "$GLOBAL_CONFIG")
DOMAIN=$(jq -r '.domainName' "$CONFIG_FILE")
POOL_APP1=$(jq -r '.routing.backendPools.app1' "$CONFIG_FILE")
PRIORITY=$(jq -r '.routing.priority' "$CONFIG_FILE")

# Configure routing
az network application-gateway address-pool create \
  --gateway-name "$AGW_NAME" \
  --name "$POOL_APP1"
```

## Configuration Validation

### Validate JSON Syntax

```bash
# Validate global configuration
jq . config/parameters-dev.json

# Validate tenant configurations
jq . config/nbrly/parameters-dev.json
jq . config/bloom/parameters-dev.json
```

### Check Required Fields

```bash
# Check if all required fields exist
jq -e '.env, .region, .resourceGroup, .containerRegistry' config/parameters-dev.json
jq -e '.tenantName, .domainName, .applications' config/nbrly/parameters-dev.json
```

### Verify Image Names

```bash
# Extract and verify all container image names
jq -r '.applications[].image' config/nbrly/parameters-dev.json
jq -r '.applications[].image' config/bloom/parameters-dev.json
```

## Environment-Specific Configuration

### Development (`parameters-dev.json`)
- **Purpose**: Local development and testing
- **Resources**: Smaller SKUs, minimal replicas
- **Domain**: `*-dev.astrapia.io`
- **WAF Mode**: Detection (for testing)
- **Auto-scaling**: 1-3 replicas

### Staging (`parameters-staging.json`) [Future]
- **Purpose**: Pre-production validation
- **Resources**: Production-like SKUs
- **Domain**: `*-staging.astrapia.io`
- **WAF Mode**: Prevention
- **Auto-scaling**: 2-5 replicas

### Production (`parameters-prod.json`) [Future]
- **Purpose**: Live production workloads
- **Resources**: High-availability, larger SKUs
- **Domain**: `*.astrapia.io`
- **WAF Mode**: Prevention
- **Auto-scaling**: 3-10 replicas

## Configuration Best Practices

### ✅ DO:
- **Version control**: Commit all configuration files (no secrets!)
- **Validate JSON**: Use `jq` to validate before deployment
- **Document changes**: Add comments in this README when modifying structure
- **Use variables**: Reference configuration in scripts, don't hardcode
- **Separate environments**: Maintain separate files for dev/staging/prod
- **Consistent naming**: Follow naming conventions defined in instructions
- **Test configurations**: Validate settings before deploying

### ❌ DON'T:
- **Store secrets**: Never put passwords, keys, or connection strings in config files
- **Hardcode values**: Always use configuration files in scripts
- **Duplicate data**: Inherit from global config when possible
- **Skip validation**: Always validate JSON syntax before committing
- **Mix environments**: Keep dev/staging/prod configurations separate
- **Ignore defaults**: Override only when necessary, use global defaults

## Secrets Management

**IMPORTANT**: Configuration files should NOT contain secrets.

### Where to Store Secrets:
- **Azure Key Vault**: Production secrets, certificates, connection strings
- **Credential Files**: Service principal credentials in `../creds/*.cred` (git-ignored)
- **Environment Variables**: Temporary secrets for local development
- **Managed Identities**: Preferred for Azure service-to-service authentication

### Example Secret References:
```json
{
  "database": {
    "connectionStringKeyVault": "kv-astrapia-dev",
    "connectionStringSecret": "postgres-connection-string"
  },
  "api": {
    "keyVault": "kv-astrapia-dev",
    "apiKeySecret": "external-api-key"
  }
}
```

## Updating Configuration

### Add New Tenant

1. Create tenant directory:
   ```bash
   mkdir -p config/newtenant
   ```

2. Create tenant configuration:
   ```bash
   cp config/nbrly/parameters-dev.json config/newtenant/parameters-dev.json
   ```

3. Update tenant-specific values:
   ```json
   {
     "tenantName": "newtenant",
     "domainName": "newtenant-dev.astrapia.io",
     "containerAppEnvironment": "cae-newtenant-dev"
   }
   ```

4. Add to global configuration:
   ```json
   {
     "customDomain": {
       "tenantDomains": {
         "nbrly": "nbrly-dev.astrapia.io",
         "bloom": "bloom-dev.astrapia.io",
         "newtenant": "newtenant-dev.astrapia.io"
       }
     }
   }
   ```

### Add New Application to Tenant

1. Edit tenant configuration (`config/nbrly/parameters-dev.json`):
   ```json
   {
     "applications": {
       "nbapp1": { ... },
       "nbapp2": { ... },
       "nbapp3": {
         "name": "ca-nbrly-nbapp3-dev",
         "image": "astradevacr.azurecr.io/nbrly/nbapp3",
         "tag": "latest",
         "port": 8000,
         "rootPath": "/app3",
         "cpu": 0.5,
         "memory": "1.0Gi"
       }
     }
   }
   ```

2. Update routing configuration:
   ```json
   {
     "routing": {
       "backendPools": {
         "app1": "pool-nbrly-app1",
         "app2": "pool-nbrly-app2",
         "app3": "pool-nbrly-app3"
       }
     }
   }
   ```

### Modify Resource Limits

1. Update global defaults for all apps:
   ```json
   {
     "containerApps": {
       "defaults": {
         "cpu": 1.0,        // Increased from 0.5
         "memory": "2.0Gi",  // Increased from 1.0Gi
         "minReplicas": 2,   // Increased from 1
         "maxReplicas": 5    // Increased from 3
       }
     }
   }
   ```

2. Or update specific application:
   ```json
   {
     "applications": {
       "nbapp1": {
         "cpu": 1.0,
         "memory": "2.0Gi",
         "minReplicas": 2,
         "maxReplicas": 5
       }
     }
   }
   ```

## Troubleshooting

### Invalid JSON Syntax
```bash
# Error: parse error: Expected separator between values
# Solution: Check for missing commas, quotes, or brackets
jq . config/parameters-dev.json
```

### Missing Configuration Values
```bash
# Error: Cannot read property 'undefined'
# Solution: Verify all required fields exist
jq -e '.applications.nbapp1.image' config/nbrly/parameters-dev.json
```

### Configuration Mismatch
```bash
# Error: Resource names don't match actual Azure resources
# Solution: Update configuration to match deployed resources
az containerapp list --resource-group rg-astrapia-dev --query "[].name" -o table
```

## Related Documentation
- [Main README](../README.md)
- [Deployment Guide](../docs/deployment-guide.md)
- [Naming Conventions](../../.github/instructions/iac-naming-convention.instructions.md)
- [Scripts Documentation](../scripts/README.md)

## Configuration Schema

For IDE autocomplete and validation, consider creating JSON schemas:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["env", "region", "project", "resourceGroup"],
  "properties": {
    "env": { "type": "string", "enum": ["dev", "staging", "prod"] },
    "region": { "type": "string" },
    "project": { "type": "string" }
  }
}
```

## Support

For questions about configuration:
1. Check this README for usage examples
2. Review existing configuration files for patterns
3. Validate JSON syntax with `jq`
4. Consult deployment scripts for how values are used
5. Review Azure naming conventions in `.github/instructions/`
