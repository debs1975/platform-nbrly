# Deployment Scripts Guide

## Overview

This directory contains the deployment scripts for multi-tenant Azure infrastructure. The scripts are organized to eliminate duplication and support parameterized deployment.

## Script Structure

### Main Deployment Scripts

1. **`00-deploy-all.sh`** - Master orchestration script
   - Deploys complete infrastructure for all tenants
   - Usage: `./00-deploy-all.sh <project> [environment]`
   - Example: `./00-deploy-all.sh astra dev`

2. **`01-deploy-common-infra.sh`** - Common/shared infrastructure
   - Resource Group, VNet, Application Gateway, Key Vault, ACR, Log Analytics
   - Usage: `./01-deploy-common-infra.sh <project> [environment]`
   - Example: `./01-deploy-common-infra.sh astra dev`

3. **`02-deploy-tenant-infra.sh`** - Tenant deployment wrapper
   - Wrapper script that calls tenant resources and routing scripts
   - Usage: `./02-deploy-tenant-infra.sh <tenant> <project> [environment]`
   - Example: `./02-deploy-tenant-infra.sh nbrly astra dev`

4. **`03-deploy-tenant-resources.sh`** - **NEW: Unified tenant resources**
   - Parameterized script for deploying any tenant's resources
   - Creates subnet, managed identity, PostgreSQL, Container App Environment, Container App
   - Usage: `./03-deploy-tenant-resources.sh <tenant> <project> [environment]`
   - Example: `./03-deploy-tenant-resources.sh nbrly astra dev`
   - Example: `./03-deploy-tenant-resources.sh bloom astra dev`

5. **`04-configure-routing.sh`** - **NEW: Unified routing configuration**
   - Parameterized script for configuring Application Gateway routing for any tenant
   - Creates backend pools, health probes, HTTP settings, listeners, routing rules
   - Usage: `./04-configure-routing.sh <tenant> <project> [environment]`
   - Example: `./04-configure-routing.sh nbrly astra dev`
   - Example: `./04-configure-routing.sh bloom astra dev`

### Legacy Tenant-Specific Scripts (Deprecated)

The following scripts are deprecated in favor of the new parameterized scripts:

- `nbrly/01-deploy-tenant-resources.sh` → Use `03-deploy-tenant-resources.sh nbrly`
- `nbrly/02-configure-routing.sh` → Use `04-configure-routing.sh nbrly`
- `bloom/01-deploy-tenant-resources.sh` → Use `03-deploy-tenant-resources.sh bloom`
- `bloom/02-configure-routing.sh` → Use `04-configure-routing.sh bloom`

## Deployment Flow

```
00-deploy-all.sh (astra, dev)
│
├─→ 01-deploy-common-infra.sh (astra, dev)
│   ├─ Resource Group
│   ├─ VNet + Subnets
│   ├─ Key Vault (with RBAC)
│   ├─ Container Registry
│   ├─ Log Analytics
│   ├─ Application Gateway
│   └─ SSL Certificate import
│
├─→ 02-deploy-tenant-infra.sh (nbrly, astra, dev)
│   ├─→ 03-deploy-tenant-resources.sh (nbrly, astra, dev)
│   │   ├─ Tenant Subnet
│   │   ├─ Managed Identity (with RBAC)
│   │   ├─ PostgreSQL Server
│   │   ├─ Container App Environment
│   │   └─ Container App
│   │
│   └─→ 04-configure-routing.sh (nbrly, astra, dev)
│       ├─ Backend Pool
│       ├─ Health Probe
│       ├─ HTTP Settings
│       ├─ HTTPS Listener
│       └─ Routing Rule
│
└─→ 02-deploy-tenant-infra.sh (bloom, astra, dev)
    ├─→ 03-deploy-tenant-resources.sh (bloom, astra, dev)
    └─→ 04-configure-routing.sh (bloom, astra, dev)
```

## Configuration Files

Each tenant has its own configuration directory:

```
config/
├── parameters-dev.json          # Common parameters
├── nbrly/
│   └── parameters-dev.json      # NBRLY tenant parameters
└── bloom/
    └── parameters-dev.json      # BLOOM tenant parameters
```

### Tenant Configuration Structure

Each tenant config must include:
- `tenantName`: Tenant identifier (e.g., "nbrly", "bloom")
- `caeSubnetPrefix`: Subnet CIDR (e.g., "10.100.10.0/24")
- `domainName`: Custom domain (e.g., "nbrly-dev.astrapia.io")

## Adding a New Tenant

1. Create tenant configuration:
   ```bash
   mkdir -p config/<new-tenant>
   # Create config/<new-tenant>/parameters-dev.json with:
   # - tenantName
   # - caeSubnetPrefix
   # - domainName
   ```

2. Update tenant validation in scripts:
   - Edit `03-deploy-tenant-resources.sh` line 46
   - Edit `04-configure-routing.sh` line 44
   - Change regex: `^(nbrly|bloom|new-tenant)$`

3. Deploy the new tenant:
   ```bash
   ./02-deploy-tenant-infra.sh <new-tenant> astra dev
   ```

## Benefits of New Structure

✅ **No code duplication**: Single script for all tenants
✅ **Easy maintenance**: Update one script instead of multiple
✅ **Scalable**: Add new tenants with just configuration
✅ **Consistent**: Same deployment logic for all tenants
✅ **Parameterized**: Tenant name as input parameter

## Usage Examples

### Full Deployment
```bash
./00-deploy-all.sh astra dev
```

### Deploy Only Common Infrastructure
```bash
./01-deploy-common-infra.sh astra dev
```

### Deploy Single Tenant
```bash
./02-deploy-tenant-infra.sh nbrly astra dev
```

### Deploy Tenant Resources Only
```bash
./03-deploy-tenant-resources.sh bloom astra dev
```

### Configure Routing Only
```bash
./04-configure-routing.sh nbrly astra dev
```

## Helper Scripts

- `helpers/logging.sh` - Logging functions (log_info, log_error, log_success)
- `helpers/azure-login.sh` - Azure authentication handling

## State Files

Generated state is stored in:
- `config/.generated/generated-infra-{env}.json` - Deployment metadata
- `config/infra-{env}.json` - Resource tracking
- `config/.generated/.bak/` - Backups of generated-infra files
- `config/.bak/` - Backups of infra files
