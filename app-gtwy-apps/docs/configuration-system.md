# Configuration Management System

This document describes the configuration management system for the multi-tenant Azure Container Apps deployment.

## Overview

The configuration system provides a centralized, environment-specific configuration management approach using JSON files. All deployment scripts use the `config-loader.sh` helper to read configuration values, ensuring consistency and eliminating hardcoded values.

## Directory Structure

```
app-gtwy-apps/
├── config/
│   ├── README.md                      # Configuration documentation
│   ├── parameters-dev.json           # Global dev configuration
│   ├── nbrly/
│   │   └── parameters-dev.json      # NBRLY tenant dev configuration
│   └── bloom/
│       └── parameters-dev.json      # BLOOM tenant dev configuration
└── scripts/
    └── helpers/
        ├── config-loader.sh          # Configuration loader utility
        └── config-example.sh         # Example usage script
```

## Configuration Files

### Global Configuration (`config/parameters-dev.json`)

Contains infrastructure-wide settings:

- **Environment**: env, region, project
- **Resources**: Resource group, ACR, VNet configuration
- **Application Gateway**: Name, SKU, WAF settings
- **Container Apps**: Default resource limits and scaling
- **Logging**: Log Analytics and Application Insights
- **Custom Domains**: SSL certificates and tenant domain mappings
- **Tags**: Azure resource tags

### Tenant Configuration (`config/{tenant}/parameters-dev.json`)

Contains tenant-specific settings:

- **Tenant Info**: Name, display name, domain
- **Networking**: Subnet prefix, Container App Environment
- **Applications**: Per-app configuration (image, resources, env vars)
- **Routing**: Backend pools, HTTP settings, routing rules
- **Monitoring**: Application-specific monitoring settings
- **Tags**: Tenant-specific resource tags

## Using Configuration in Scripts

### 1. Load the Config Loader

At the beginning of your script:

```bash
#!/bin/bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Set environment
ENV=${ENV:-"dev"}
```

### 2. Check Prerequisites

```bash
# Check if jq is installed
check_jq || exit 1
```

### 3. Read Global Configuration Values

```bash
# Read global configuration
RESOURCE_GROUP=$(get_global_value "$ENV" ".resourceGroup")
REGION=$(get_global_value "$ENV" ".region")
ACR_NAME=$(get_global_value "$ENV" ".containerRegistry")
AGW_NAME=$(get_global_value "$ENV" ".applicationGateway.name")
```

### 4. Read Tenant Configuration Values

```bash
# Set tenant
TENANT="nbrly"

# Read tenant configuration
DOMAIN=$(get_tenant_value "$TENANT" "$ENV" ".domainName")
CAE_NAME=$(get_tenant_value "$TENANT" "$ENV" ".containerAppEnvironment")
SUBNET=$(get_tenant_value "$TENANT" "$ENV" ".caeSubnetPrefix")
```

### 5. Read Application Configuration

```bash
# Set application
APP="nbapp1"

# Read application configuration
APP_NAME=$(get_app_config "$TENANT" "$APP" "$ENV" "name")
IMAGE=$(get_app_config "$TENANT" "$APP" "$ENV" "image")
TAG=$(get_app_config "$TENANT" "$APP" "$ENV" "tag")
CPU=$(get_app_config "$TENANT" "$APP" "$ENV" "cpu")
MEMORY=$(get_app_config "$TENANT" "$APP" "$ENV" "memory")
```

### 6. Iterate Over All Applications

```bash
# Get all applications for a tenant
while IFS= read -r app; do
    app_name=$(get_app_config "$TENANT" "$app" "$ENV" "name")
    app_image=$(get_app_config "$TENANT" "$app" "$ENV" "image")
    echo "Deploying: $app_name with image: $app_image"
done < <(get_tenant_applications "$TENANT" "$ENV")
```

## Available Functions

### Configuration Loading

| Function | Description | Example |
|----------|-------------|---------|
| `check_jq` | Check if jq is installed | `check_jq \|\| exit 1` |
| `load_global_config <env>` | Get global config file path | `config=$(load_global_config "dev")` |
| `load_tenant_config <tenant> <env>` | Get tenant config file path | `config=$(load_tenant_config "nbrly" "dev")` |

### Value Retrieval

| Function | Description | Example |
|----------|-------------|---------|
| `get_global_value <env> <path>` | Get value from global config | `rg=$(get_global_value "dev" ".resourceGroup")` |
| `get_tenant_value <tenant> <env> <path>` | Get value from tenant config | `domain=$(get_tenant_value "nbrly" "dev" ".domainName")` |
| `get_app_config <tenant> <app> <env> <prop>` | Get app property | `image=$(get_app_config "nbrly" "nbapp1" "dev" "image")` |
| `get_tenant_applications <tenant> <env>` | List all apps for tenant | `get_tenant_applications "nbrly" "dev"` |

### Environment Variables

| Function | Description | Example |
|----------|-------------|---------|
| `export_global_config <env>` | Export global config as env vars | `export_global_config "dev"` |
| `export_tenant_config <tenant> <env>` | Export tenant config as env vars | `export_tenant_config "nbrly" "dev"` |

### Validation

| Function | Description | Example |
|----------|-------------|---------|
| `validate_config <env>` | Validate all config files | `validate_config "dev"` |
| `print_config_summary <env> [tenant]` | Print config summary | `print_config_summary "dev" "nbrly"` |

## Command-Line Usage

The `config-loader.sh` script can also be used directly from the command line:

```bash
# Validate configuration
./scripts/helpers/config-loader.sh validate dev

# Print configuration summary (all tenants)
./scripts/helpers/config-loader.sh summary dev

# Print configuration summary (specific tenant)
./scripts/helpers/config-loader.sh summary dev nbrly

# Export global configuration as environment variables
source ./scripts/helpers/config-loader.sh export-global dev
echo $CONFIG_RESOURCE_GROUP

# Export tenant configuration as environment variables
source ./scripts/helpers/config-loader.sh export-tenant nbrly dev
echo $TENANT_DOMAIN
```

## Updated Scripts

The following scripts have been updated to use the configuration system:

### Build Scripts
- `scripts/build-push-nbrly.sh` - Reads ACR name and image names from config
- `scripts/build-push-bloom.sh` - Reads ACR name and image names from config
- `scripts/build-push-all.sh` - Uses tenant configurations

### Deployment Scripts
- `scripts/deploy-nbrly.sh` - Reads all deployment parameters from config
- `scripts/deploy-bloom.sh` - Reads all deployment parameters from config
- `scripts/04-deploy-all.sh` - Uses tenant configurations

### Routing Scripts
- `scripts/08-configure-routing.sh` - Reads Application Gateway and domain config
- `scripts/routing/configure-routing-nbrly.sh` - Uses NBRLY tenant config
- `scripts/routing/configure-routing-bloom.sh` - Uses BLOOM tenant config

## Configuration Examples

### Example 1: Build Script

```bash
#!/bin/bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/config-loader.sh"

ENV=${ENV:-"dev"}
TENANT="nbrly"

# Read configuration
check_jq || exit 1
ACR_NAME=$(get_global_value "$ENV" ".containerRegistry")

# Build all applications for tenant
while IFS= read -r app; do
    image=$(get_app_config "$TENANT" "$app" "$ENV" "image")
    tag=$(get_app_config "$TENANT" "$app" "$ENV" "tag")
    
    echo "Building: $image:$tag"
    docker build -t "$image:$tag" "./$TENANT/$app/"
    docker push "$image:$tag"
done < <(get_tenant_applications "$TENANT" "$ENV")
```

### Example 2: Deployment Script

```bash
#!/bin/bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/config-loader.sh"

ENV=${ENV:-"dev"}
TENANT="nbrly"
APP="nbapp1"

# Read configuration
check_jq || exit 1
RESOURCE_GROUP=$(get_global_value "$ENV" ".resourceGroup")
CAE_NAME=$(get_tenant_value "$TENANT" "$ENV" ".containerAppEnvironment")
APP_NAME=$(get_app_config "$TENANT" "$APP" "$ENV" "name")
IMAGE=$(get_app_config "$TENANT" "$APP" "$ENV" "image")
TAG=$(get_app_config "$TENANT" "$APP" "$ENV" "tag")
CPU=$(get_app_config "$TENANT" "$APP" "$ENV" "cpu")
MEMORY=$(get_app_config "$TENANT" "$APP" "$ENV" "memory")

# Deploy Container App
az containerapp create \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$CAE_NAME" \
  --image "$IMAGE:$TAG" \
  --cpu "$CPU" \
  --memory "$MEMORY"
```

### Example 3: Routing Script

```bash
#!/bin/bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/config-loader.sh"

ENV=${ENV:-"dev"}
TENANT="nbrly"

# Read configuration
check_jq || exit 1
RESOURCE_GROUP=$(get_global_value "$ENV" ".resourceGroup")
AGW_NAME=$(get_global_value "$ENV" ".applicationGateway.name")
DOMAIN=$(get_tenant_value "$TENANT" "$ENV" ".domainName")
POOL_APP1=$(get_tenant_value "$TENANT" "$ENV" ".routing.backendPools.app1")

# Configure Application Gateway
az network application-gateway address-pool create \
  --gateway-name "$AGW_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$POOL_APP1"
```

## Environment-Specific Configuration

### Development Environment

```bash
# Use default (dev) environment
./scripts/build-push-nbrly.sh

# Explicitly set dev environment
ENV=dev ./scripts/build-push-nbrly.sh
```

### Staging Environment (Future)

```bash
# Use staging environment
ENV=staging ./scripts/build-push-nbrly.sh
```

### Production Environment (Future)

```bash
# Use production environment
ENV=prod ./scripts/build-push-nbrly.sh
```

## Adding New Configuration

### Add New Tenant

1. Create tenant configuration directory:
   ```bash
   mkdir -p config/newtenant
   ```

2. Create tenant configuration file:
   ```bash
   cp config/nbrly/parameters-dev.json config/newtenant/parameters-dev.json
   ```

3. Update tenant-specific values in `config/newtenant/parameters-dev.json`

4. Add tenant to global configuration:
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

Edit `config/{tenant}/parameters-dev.json`:

```json
{
  "applications": {
    "app1": { ... },
    "app2": { ... },
    "app3": {
      "name": "ca-tenant-app3-dev",
      "image": "astradevacr.azurecr.io/tenant/app3",
      "tag": "latest",
      "port": 8000,
      "rootPath": "/app3",
      "cpu": 0.5,
      "memory": "1.0Gi",
      "minReplicas": 1,
      "maxReplicas": 3
    }
  }
}
```

## Best Practices

### ✅ DO:
- **Use config-loader.sh** in all deployment scripts
- **Validate configuration** before running deployments
- **Keep secrets out** of configuration files (use Azure Key Vault)
- **Document changes** when modifying configuration structure
- **Test configurations** after updates with `validate_config`
- **Use consistent paths** when accessing nested configuration
- **Handle missing values** gracefully with default values

### ❌ DON'T:
- **Hardcode values** - always use configuration files
- **Store secrets** - use Azure Key Vault references instead
- **Duplicate configuration** - inherit from global defaults when possible
- **Skip validation** - always validate JSON before committing
- **Mix environments** - keep clear separation between dev/staging/prod
- **Ignore errors** - check return values from config functions

## Troubleshooting

### Configuration Not Found

```bash
# Error: configuration file not found
# Solution: Verify file exists and path is correct
ls -la config/parameters-dev.json
ls -la config/nbrly/parameters-dev.json
```

### Invalid JSON

```bash
# Error: parse error
# Solution: Validate JSON syntax
jq . config/parameters-dev.json
```

### jq Not Installed

```bash
# Error: jq is not installed
# Solution: Install jq
brew install jq                    # macOS
sudo apt-get install jq           # Ubuntu/Debian
sudo yum install jq               # RHEL/CentOS
```

### Value Not Found

```bash
# Error: value not found for path
# Solution: Check JSON path and structure
jq '.resourceGroup' config/parameters-dev.json
jq '.applications.nbapp1.image' config/nbrly/parameters-dev.json
```

## Testing Configuration

### Validate All Configuration Files

```bash
cd scripts/helpers
./config-loader.sh validate dev
```

### Print Configuration Summary

```bash
# All tenants
./config-loader.sh summary dev

# Specific tenant
./config-loader.sh summary dev nbrly
```

### Test Configuration Loading

```bash
# Run example script
./config-example.sh dev nbrly nbapp1
```

### Manual Testing

```bash
# Source the config loader
source ./scripts/helpers/config-loader.sh

# Test individual functions
get_global_value "dev" ".resourceGroup"
get_tenant_value "nbrly" "dev" ".domainName"
get_app_config "nbrly" "nbapp1" "dev" "image"
```

## Migration from Hardcoded Values

If you have existing scripts with hardcoded values:

### Before (Hardcoded):

```bash
RESOURCE_GROUP="rg-astrapia-dev"
ACR_NAME="astradevacr"
APP_NAME="ca-nbrly-nbapp1-dev"
```

### After (Configuration):

```bash
# Load configuration
source "$SCRIPT_DIR/helpers/config-loader.sh"
check_jq || exit 1

RESOURCE_GROUP=$(get_global_value "dev" ".resourceGroup")
ACR_NAME=$(get_global_value "dev" ".containerRegistry")
APP_NAME=$(get_app_config "nbrly" "nbapp1" "dev" "name")
```

## Related Documentation

- [Configuration README](../config/README.md) - Detailed configuration file documentation
- [Build Scripts](./build-push/README.md) - Build and push documentation
- [Deployment Scripts](./deploy/README.md) - Deployment documentation
- [Routing Scripts](./routing/README.md) - Routing configuration documentation

## Support

For configuration issues:
1. Validate configuration with `./config-loader.sh validate dev`
2. Check configuration summary with `./config-loader.sh summary dev`
3. Test with example script: `./config-example.sh`
4. Review JSON syntax with `jq`
5. Consult this documentation for usage patterns
