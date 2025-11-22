# Configuration Migration Summary

This document summarizes the configuration files copied from `iac-cli` to `app-gtwy-apps` and how they are used.

## Configuration Files Copied

### Source: `iac-cli/config/`

The following configuration structure from `iac-cli` was copied and enhanced for `app-gtwy-apps`:

```
iac-cli/config/
├── parameters-dev.json          → app-gtwy-apps/config/parameters-dev.json
├── nbrly/
│   └── parameters-dev.json     → app-gtwy-apps/config/nbrly/parameters-dev.json
└── bloom/
    └── parameters-dev.json     → app-gtwy-apps/config/bloom/parameters-dev.json
```

## Configuration Enhancements

### Global Configuration (`config/parameters-dev.json`)

**Copied from iac-cli:**
- ✅ `env`, `region`, `project`
- ✅ `vnetAddressPrefix`, `appGatewaySubnetPrefix`
- ✅ `customDomain` with tenant domain mappings

**Added for app-gtwy-apps:**
- ➕ `resourceGroup` - Target resource group for deployments
- ➕ `containerRegistry` - Azure Container Registry name
- ➕ `applicationGateway` - Application Gateway configuration (name, SKU, WAF)
- ➕ `containerApps` - Default Container App resource limits
- ➕ `logging` - Log Analytics and Application Insights configuration
- ➕ `tags` - Azure resource tags for governance

### Tenant Configuration (`config/{tenant}/parameters-dev.json`)

**Copied from iac-cli:**
- ✅ `tenantName`
- ✅ `caeSubnetPrefix`
- ✅ `domainName`

**Added for app-gtwy-apps:**
- ➕ `tenantDisplayName` - Human-readable tenant name
- ➕ `containerAppEnvironment` - Container App Environment name
- ➕ `applications` - Complete application configurations:
  - `name` - Container App name
  - `image` - Full container image path
  - `tag` - Image tag
  - `port` - Application port
  - `rootPath` - FastAPI root path
  - `cpu`, `memory` - Resource limits
  - `minReplicas`, `maxReplicas` - Auto-scaling configuration
  - `env` - Environment variables
- ➕ `routing` - Application Gateway routing configuration:
  - `backendPools` - Backend pool names
  - `httpSettings` - HTTP settings names
  - `pathMap` - URL path map name
  - `listener` - Listener name
  - `rule` - Routing rule name
  - `priority` - Rule priority
- ➕ `monitoring` - Application Insights configuration
- ➕ `tags` - Tenant-specific resource tags

## Configuration Usage in Scripts

### 1. Build Scripts

**Scripts Updated:**
- `scripts/build-push-nbrly.sh`
- `scripts/build-push-bloom.sh`
- `scripts/build-push-all.sh`

**Configuration Used:**
```bash
# From global config
ACR_NAME=$(get_global_value "$ENV" ".containerRegistry")

# From tenant config
APP_IMAGE=$(get_app_config "$TENANT" "$APP" "$ENV" "image")
APP_TAG=$(get_app_config "$TENANT" "$APP" "$ENV" "tag")

# Example usage
docker build -t "$APP_IMAGE:$APP_TAG" .
docker push "$APP_IMAGE:$APP_TAG"
```

### 2. Deployment Scripts

**Scripts Updated:**
- `scripts/deploy-nbrly.sh`
- `scripts/deploy-bloom.sh`
- `scripts/deploy-all.sh`

**Configuration Used:**
```bash
# From global config
RESOURCE_GROUP=$(get_global_value "$ENV" ".resourceGroup")
REGION=$(get_global_value "$ENV" ".region")
ACR_NAME=$(get_global_value "$ENV" ".containerRegistry")

# From tenant config
CAE_NAME=$(get_tenant_value "$TENANT" "$ENV" ".containerAppEnvironment")

# From application config
APP_NAME=$(get_app_config "$TENANT" "$APP" "$ENV" "name")
IMAGE=$(get_app_config "$TENANT" "$APP" "$ENV" "image")
CPU=$(get_app_config "$TENANT" "$APP" "$ENV" "cpu")
MEMORY=$(get_app_config "$TENANT" "$APP" "$ENV" "memory")
MIN_REPLICAS=$(get_app_config "$TENANT" "$APP" "$ENV" "minReplicas")
MAX_REPLICAS=$(get_app_config "$TENANT" "$APP" "$ENV" "maxReplicas")

# Example usage
az containerapp create \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$CAE_NAME" \
  --image "$IMAGE:$TAG" \
  --cpu "$CPU" \
  --memory "$MEMORY" \
  --min-replicas "$MIN_REPLICAS" \
  --max-replicas "$MAX_REPLICAS"
```

### 3. Routing Scripts

**Scripts Updated:**
- `scripts/configure-routing.sh`
- `scripts/routing/configure-routing-nbrly.sh`
- `scripts/routing/configure-routing-bloom.sh`

**Configuration Used:**
```bash
# From global config
RESOURCE_GROUP=$(get_global_value "$ENV" ".resourceGroup")
AGW_NAME=$(get_global_value "$ENV" ".applicationGateway.name")

# From tenant config
DOMAIN=$(get_tenant_value "$TENANT" "$ENV" ".domainName")
POOL_APP1=$(get_tenant_value "$TENANT" "$ENV" ".routing.backendPools.app1")
SETTINGS_APP1=$(get_tenant_value "$TENANT" "$ENV" ".routing.httpSettings.app1")
PRIORITY=$(get_tenant_value "$TENANT" "$ENV" ".routing.priority")

# Example usage
az network application-gateway address-pool create \
  --gateway-name "$AGW_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$POOL_APP1"
```

### 4. YAML Manifests

**Manifests Updated:**
- `manifests/nbrly/nbapp1-containerapp.yaml`
- `manifests/nbrly/nbapp2-containerapp.yaml`
- `manifests/bloom/bmapp1-containerapp.yaml`
- `manifests/bloom/bmapp2-containerapp.yaml`

**Configuration Mapping:**
```yaml
# From tenant config
name: "#{TENANT_APP_NAME}#"  # .applications.{app}.name
environment:
  id: "#{CAE_ID}#"            # .containerAppEnvironment

# From application config
template:
  containers:
    - image: "#{APP_IMAGE}#:#{APP_TAG}#"  # .applications.{app}.image:.tag
      resources:
        cpu: "#{CPU}#"                     # .applications.{app}.cpu
        memory: "#{MEMORY}#"               # .applications.{app}.memory
      env:
        - name: ROOT_PATH
          value: "#{ROOT_PATH}#"           # .applications.{app}.rootPath
  scale:
    minReplicas: "#{MIN_REPLICAS}#"       # .applications.{app}.minReplicas
    maxReplicas: "#{MAX_REPLICAS}#"       # .applications.{app}.maxReplicas
```

## New Helper Scripts

### Configuration Loader (`scripts/helpers/config-loader.sh`)

Provides functions to load and parse JSON configuration files:

**Key Functions:**
- `check_jq` - Verify jq installation
- `load_global_config <env>` - Load global configuration
- `load_tenant_config <tenant> <env>` - Load tenant configuration
- `get_global_value <env> <path>` - Get global configuration value
- `get_tenant_value <tenant> <env> <path>` - Get tenant configuration value
- `get_app_config <tenant> <app> <env> <property>` - Get application property
- `get_tenant_applications <tenant> <env>` - List all applications
- `export_global_config <env>` - Export global config as env vars
- `export_tenant_config <tenant> <env>` - Export tenant config as env vars
- `validate_config <env>` - Validate all configuration files
- `print_config_summary <env> [tenant]` - Print configuration summary

**Command-Line Usage:**
```bash
# Validate configuration
./scripts/helpers/config-loader.sh validate dev

# Print summary
./scripts/helpers/config-loader.sh summary dev nbrly

# Export configuration
source ./scripts/helpers/config-loader.sh export-global dev
```

### Configuration Example (`scripts/helpers/config-example.sh`)

Demonstrates how to use the configuration loader in custom scripts.

**Usage:**
```bash
./scripts/helpers/config-example.sh dev nbrly nbapp1
```

## Configuration Validation

### Validation Results

```bash
$ ./scripts/helpers/config-loader.sh validate dev

Validating configuration files for environment: dev

Checking global configuration...
✓ Global configuration is valid
Checking nbrly tenant configuration...
✓ nbrly tenant configuration is valid
Checking bloom tenant configuration...
✓ bloom tenant configuration is valid

All configuration files are valid!
```

### Configuration Summary

```bash
$ ./scripts/helpers/config-loader.sh summary dev nbrly

Configuration Summary (dev)
================================

Global Configuration:
  Environment: dev
  Region: eastus
  Project: astra
  Resource Group: rg-astrapia-dev
  Container Registry: astradevacr
  Application Gateway: agw-astrapia-dev
  VNet Prefix: 10.100.0.0/16

Tenant Configuration (nbrly):
  Tenant Name: nbrly
  Domain: nbrly-dev.astrapia.io
  Container App Environment: cae-nbrly-dev
  Subnet: 10.100.10.0/24

  Applications:
    - nbapp1: ca-nbrly-nbapp1-dev
      Image: astradevacr.azurecr.io/nbrly/nbapp1
      Root Path: /app1
    - nbapp2: ca-nbrly-nbapp2-dev
      Image: astradevacr.azurecr.io/nbrly/nbapp2
      Root Path: /app2
```

## Benefits of Configuration System

### ✅ Centralized Management
- Single source of truth for all configuration
- Easy to update values across all scripts
- Consistent naming and values

### ✅ Environment Separation
- Clear separation between dev/staging/prod
- Easy to switch environments with `ENV` variable
- No hardcoded environment-specific values

### ✅ Maintainability
- No hardcoded values in scripts
- Easy to add new tenants or applications
- Configuration changes don't require script modifications

### ✅ Validation
- JSON syntax validation with `jq`
- Configuration validation before deployment
- Summary view for verification

### ✅ Documentation
- Self-documenting configuration structure
- Clear JSON schema with nested organization
- Easy to understand tenant and application relationships

## Migration Guide

### For Existing Scripts

**Before (Hardcoded):**
```bash
#!/bin/bash
RESOURCE_GROUP="rg-astrapia-dev"
ACR_NAME="astradevacr"
APP_NAME="ca-nbrly-nbapp1-dev"
```

**After (Configuration-Based):**
```bash
#!/bin/bash
source "$SCRIPT_DIR/helpers/config-loader.sh"
check_jq || exit 1

ENV=${ENV:-"dev"}
TENANT="nbrly"
APP="nbapp1"

RESOURCE_GROUP=$(get_global_value "$ENV" ".resourceGroup")
ACR_NAME=$(get_global_value "$ENV" ".containerRegistry")
APP_NAME=$(get_app_config "$TENANT" "$APP" "$ENV" "name")
```

### For New Scripts

1. **Source the config loader:**
   ```bash
   source "$SCRIPT_DIR/helpers/config-loader.sh"
   ```

2. **Check prerequisites:**
   ```bash
   check_jq || exit 1
   ```

3. **Load configuration:**
   ```bash
   VALUE=$(get_global_value "$ENV" ".path.to.value")
   ```

4. **Use configuration:**
   ```bash
   az resource create --name "$VALUE"
   ```

## File Locations

### Configuration Files
- `app-gtwy-apps/config/parameters-dev.json` - Global configuration
- `app-gtwy-apps/config/nbrly/parameters-dev.json` - NBRLY tenant config
- `app-gtwy-apps/config/bloom/parameters-dev.json` - BLOOM tenant config

### Helper Scripts
- `app-gtwy-apps/scripts/helpers/config-loader.sh` - Configuration loader
- `app-gtwy-apps/scripts/helpers/config-example.sh` - Usage example

### Documentation
- `app-gtwy-apps/config/README.md` - Configuration file documentation
- `app-gtwy-apps/docs/configuration-system.md` - System documentation
- This file - Migration summary

## Next Steps

1. ✅ **Configuration copied** from `iac-cli` to `app-gtwy-apps`
2. ✅ **Enhanced configurations** with application-specific settings
3. ✅ **Created config loader** helper script
4. ✅ **Updated all scripts** to use configuration
5. ✅ **Validated configuration** files
6. ⬜ **Test deployments** using configuration-based scripts
7. ⬜ **Add staging/prod** configurations when needed

## Testing Checklist

- [x] Configuration files validated with `jq`
- [x] Config loader script tested
- [x] Configuration summary verified
- [x] Example script demonstrates usage
- [ ] Build scripts tested with configuration
- [ ] Deployment scripts tested with configuration
- [ ] Routing scripts tested with configuration
- [ ] YAML manifests deployed with configuration values

## Related Documentation

- [Configuration README](../config/README.md)
- [Configuration System Documentation](../docs/configuration-system.md)
- [Main README](../README.md)
- [app-gtwy-apps Configuration](../config/README.md)
