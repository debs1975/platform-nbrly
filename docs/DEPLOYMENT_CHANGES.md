# Deployment Script Changes - Project-Based Infrastructure

Date: 2025-11-21
Branch: `feature-appgtwy`

## Summary

Updated all `iac-cli/scripts` deployment scripts to:
1. **Accept PROJECT parameter** - Resource names are now derived from `<project>-<environment>-<region>` pattern
2. **Print inferred variables** - All resource names are displayed before creation
3. **Track resources in `infra-{ENV}.json`** - Separate tracking file that stores created resource names per environment

## Changes by Script

### Main Orchestration Scripts

#### `00-deploy-all.sh`
- **New Usage**: `./00-deploy-all.sh <project> [environment]`
- **Example**: `./00-deploy-all.sh astra dev`
- **Changes**:
  - Added required `PROJECT` parameter (first argument)
  - Passes PROJECT to all child scripts
  - Prints project name in deployment header

#### `01-deploy-common-infra.sh`
- **New Usage**: `./01-deploy-common-infra.sh <project> [environment]`
- **Example**: `./01-deploy-common-infra.sh astra dev`
- **Changes**:
  - Added required `PROJECT` parameter
  - Derives all resource names from `project`, `ENV`, and `region`
  - Prints all inferred variables before deployment in formatted table
  - Creates `infra-{ENV}.json` tracking file alongside `generated-infra-{ENV}.json`
  - Updates `infra-{ENV}.json` after each resource creation

**Inferred Variables Printed**:
```
Project:              astra
Environment:          dev
Region:               eastus
Resource Group:       astra-dev-eastus-rg
VNet:                 astra-dev-eastus-vnet
VNet Address Prefix:  10.100.0.0/16
App Gateway:          astra-dev-eastus-agw
Public IP:            astra-dev-eastus-pip
Key Vault:            astradeveastuskv
Container Registry:   astradeveastusacr
Log Analytics:        astra-dev-eastus-law
AGW Managed Identity: agw-managed-identity
```

**Resources Tracked in `infra-{ENV}.json`**:
- Resource Group (name, id)
- VNet (name, id)
- Log Analytics Workspace (name, id)
- Container Registry (name, id)
- Key Vault (name, id)
- Public IP (name, id, ipAddress)
- Application Gateway (name, id)

#### `02-deploy-tenant-infra.sh`
- **New Usage**: `./02-deploy-tenant-infra.sh <tenant> <project> [environment]`
- **Example**: `./02-deploy-tenant-infra.sh nbrly astra dev`
- **Changes**:
  - Added required `PROJECT` parameter (second argument)
  - Passes PROJECT to tenant deployment and routing scripts

### Tenant Deployment Scripts

#### `nbrly/01-deploy-tenant-resources.sh` and `bloom/01-deploy-tenant-resources.sh`
- **New Usage**: `./01-deploy-tenant-resources.sh <project> [environment]`
- **Example**: `./01-deploy-tenant-resources.sh astra dev`
- **Changes**:
  - Added required `PROJECT` parameter
  - Derives tenant resource names from `tenantName`, `env`, and `region`
  - Prints all inferred tenant variables before deployment
  - Updates `infra-{ENV}.json` after each tenant resource creation

**Inferred Tenant Variables Printed**:
```
Project:              astra
Tenant:               nbrly
Environment:          dev
Region:               eastus
CAE Subnet:           snet-nbrly-dev-cae
CAE Subnet Prefix:    10.100.10.0/23
Container App Env:    nbrly-dev-cae
Managed Identity:     nbrly-dev-uami
PostgreSQL Server:    nbrly-dev-psql
Container App:        nbrly-dev-app1-ca
Domain Name:          nbrly-dev.astrapia.io
```

**Tenant Resources Tracked in `infra-{ENV}.json`**:
- Subnet (name, id)
- Managed Identity (name, id)
- PostgreSQL Server (name, id)
- Container App Environment (name, id)
- Container App (name, id, fqdn)

#### `nbrly/02-configure-routing.sh` and `bloom/02-configure-routing.sh`
- **New Usage**: `./02-configure-routing.sh <project> [environment]`
- **Example**: `./02-configure-routing.sh astra dev`
- **Changes**:
  - Added required `PROJECT` parameter
  - Updated usage documentation

## File Structure

### Configuration Files
- `iac-cli/config/parameters-{ENV}.json` - Input parameters (unchanged)
- `iac-cli/config/{tenant}/parameters-{ENV}.json` - Tenant-specific parameters (unchanged)

### Generated Files
- `iac-cli/config/.generated/generated-infra-{ENV}.json` - Complete deployment state (existing, unchanged structure)
- **`iac-cli/config/infra-{ENV}.json`** - **NEW** - Resource tracking file with simplified structure

### `infra-{ENV}.json` Structure
```json
{
  "project": "astra",
  "environment": "dev",
  "resources": {
    "resourceGroup": {"name": "...", "id": "..."},
    "vnet": {"name": "...", "id": "..."},
    "logAnalytics": {"name": "...", "id": "..."},
    "containerRegistry": {"name": "...", "id": "..."},
    "keyVault": {"name": "...", "id": "..."},
    "publicIp": {"name": "...", "id": "...", "ipAddress": "..."},
    "applicationGateway": {"name": "...", "id": "..."},
    "tenants": {
      "nbrly": {
        "subnet": {"name": "...", "id": "..."},
        "managedIdentity": {"name": "...", "id": "..."},
        "postgresServer": {"name": "...", "id": "..."},
        "containerAppEnv": {"name": "...", "id": "..."},
        "containerApp": {"name": "...", "id": "...", "fqdn": "..."}
      },
      "bloom": {
        "subnet": {"name": "...", "id": "..."},
        "managedIdentity": {"name": "...", "id": "..."},
        "postgresServer": {"name": "...", "id": "..."},
        "containerAppEnv": {"name": "...", "id": "..."},
        "containerApp": {"name": "...", "id": "...", "fqdn": "..."}
      }
    }
  }
}
```

## Resource Naming Convention

All resources now follow consistent naming patterns derived from project, environment, and region:

### Common Resources
- Resource Group: `{project}-{env}-{region}-rg`
- VNet: `{project}-{env}-{region}-vnet`
- Application Gateway: `{project}-{env}-{region}-agw`
- Public IP: `{project}-{env}-{region}-pip`
- Log Analytics: `{project}-{env}-{region}-law`
- Key Vault: `{project}{env}{region}kv` (no dashes due to naming restrictions)
- Container Registry: `{project}{env}{region}acr` (no dashes due to naming restrictions)

### Tenant Resources
- Subnet: `snet-{tenant}-{env}-cae`
- Container App Environment: `{tenant}-{env}-cae`
- Managed Identity: `{tenant}-{env}-uami`
- PostgreSQL Server: `{tenant}-{env}-psql`
- Container App: `{tenant}-{env}-app1-ca`

## Usage Examples

### Deploy Everything
```bash
cd iac-cli/scripts
./00-deploy-all.sh astra dev
./00-deploy-all.sh astra stage
./00-deploy-all.sh astra prod
```

### Deploy Common Infrastructure Only
```bash
cd iac-cli/scripts
./01-deploy-common-infra.sh astra dev
```

### Deploy Specific Tenant
```bash
cd iac-cli/scripts
./02-deploy-tenant-infra.sh nbrly astra dev
./02-deploy-tenant-infra.sh bloom astra prod
```

### Deploy Tenant Resources Directly
```bash
cd iac-cli/scripts/nbrly
./01-deploy-tenant-resources.sh astra dev
./02-configure-routing.sh astra dev
```

## Variable Inference Logic

Variables are inferred in this order:
1. **PROJECT** - From script parameter (required)
2. **ENV** - From script parameter (defaults to `dev`)
3. **region** - From config file (defaults to `eastus` if not in config)
4. **Resource names** - Derived using the naming convention patterns above

The scripts print all inferred variables in a formatted table before creating any resources, allowing you to verify names before deployment.

## Backward Compatibility

**Breaking Change**: All scripts now require the PROJECT parameter as the first argument. Previous invocations like:

```bash
# OLD (no longer works)
./00-deploy-all.sh dev
./01-deploy-common-infra.sh dev
./02-deploy-tenant-infra.sh nbrly dev
```

Must be updated to:

```bash
# NEW (required)
./00-deploy-all.sh astra dev
./01-deploy-common-infra.sh astra dev
./02-deploy-tenant-infra.sh nbrly astra dev
```

## Benefits

1. **Explicit Project Naming** - Project name is now a clear, required parameter
2. **Pre-Creation Visibility** - See all resource names before they're created
3. **Resource Tracking** - `infra-{ENV}.json` provides a clean inventory of created resources
4. **Environment Isolation** - Each environment gets its own tracking file
5. **Simplified Debugging** - Easy to verify resource names match expectations
6. **CI/CD Friendly** - Clear parameter structure for automation

## Testing

Tested with:
- Parameter validation (missing project parameter correctly rejected)
- Variable printing (all inferred variables displayed before deployment)
- File creation (`infra-dev.json` created with correct structure)
- Resource tracking (resource names and IDs written to tracking file after creation)

## Next Steps

Consider:
- Add `infra-*.json` files to `.gitignore` if they shouldn't be version controlled
- Create validation script to check tracking file consistency
- Add CI/CD pipeline examples using the new parameter structure
- Document migration guide for existing deployments
