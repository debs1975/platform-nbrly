# IaC CLI Scripts - Environment-Based Deployment

This directory contains infrastructure-as-code deployment scripts that support multiple environments (dev, stage, prod).

## Usage

### Deploy All Infrastructure

```bash
# Deploy to development (default)
./00-deploy-all.sh

# Deploy to specific environment
./00-deploy-all.sh dev
./00-deploy-all.sh stage
./00-deploy-all.sh prod
```

### Deploy Common Infrastructure Only

```bash
# Deploy common resources (VNet, ACR, Key Vault, App Gateway)
./01-deploy-common-infra.sh dev
./01-deploy-common-infra.sh stage
./01-deploy-common-infra.sh prod
```

### Deploy Tenant Infrastructure

```bash
# Deploy specific tenant
./02-deploy-tenant-infra.sh nbrly dev
./02-deploy-tenant-infra.sh bloom stage

# Deploy both tenants for an environment
./02-deploy-tenant-infra.sh nbrly prod
./02-deploy-tenant-infra.sh bloom prod
```

### Deploy Individual Tenant Components

```bash
# From tenant directory (nbrly or bloom)
cd nbrly
./01-deploy-tenant-resources.sh dev
./02-configure-routing.sh dev

cd ../bloom
./01-deploy-tenant-resources.sh stage
./02-configure-routing.sh stage
```

## Environment Configuration

### Configuration Files

Each environment has its own configuration files:

```
config/
├── parameters-dev.json          # Development environment
├── parameters-stage.json        # Staging environment
├── parameters-prod.json         # Production environment
├── nbrly/
│   ├── parameters-dev.json
│   ├── parameters-stage.json
│   └── parameters-prod.json
└── bloom/
    ├── parameters-dev.json
    ├── parameters-stage.json
    └── parameters-prod.json
```

### Generated State Files

Deployment state is stored in environment-specific files:

```
config/.generated/
├── generated-infra-dev.json
├── generated-infra-stage.json
└── generated-infra-prod.json
```

## Environment Differences

### Development (dev)
- VNet: `10.100.0.0/16`
- Domains: `*-dev.astrapia.io`
- Certificate: `astrapia-io-dev.pfx`
- Resource naming: `astra-dev-*`

### Staging (stage)
- VNet: `10.200.0.0/16`
- Domains: `*-stage.astrapia.io`
- Certificate: `astrapia-io-stage.pfx`
- Resource naming: `astra-stage-*`

### Production (prod)
- VNet: `10.0.0.0/16`
- Domains: `*.astrapia.io` (no environment suffix)
- Certificate: `astrapia-io-prod.pfx`
- Resource naming: `astra-prod-*`

## Script Overview

### Main Scripts

| Script | Purpose | Environment Parameter |
|--------|---------|----------------------|
| `00-deploy-all.sh` | Orchestrates full deployment | `[dev\|stage\|prod]` (default: dev) |
| `01-deploy-common-infra.sh` | Deploys shared infrastructure | `[dev\|stage\|prod]` (default: dev) |
| `02-deploy-tenant-infra.sh` | Deploys tenant-specific resources | `<tenant> [env]` (default: dev) |

### Tenant Scripts

Located in `nbrly/` and `bloom/` directories:

| Script | Purpose | Environment Parameter |
|--------|---------|----------------------|
| `01-deploy-tenant-resources.sh` | Creates UAMI, PostgreSQL, Container Apps | `[dev\|stage\|prod]` (default: dev) |
| `02-configure-routing.sh` | Configures Application Gateway routing | `[dev\|stage\|prod]` (default: dev) |

## Deployment Flow

```
00-deploy-all.sh <env>
├── 01-deploy-common-infra.sh <env>
│   ├── Creates Resource Group
│   ├── Creates VNet with subnets
│   ├── Creates Log Analytics Workspace
│   ├── Creates Azure Container Registry
│   ├── Creates Key Vault
│   ├── Uploads SSL Certificate
│   └── Creates Application Gateway
├── 02-deploy-tenant-infra.sh nbrly <env>
│   ├── nbrly/01-deploy-tenant-resources.sh <env>
│   │   ├── Creates tenant subnet
│   │   ├── Creates User Assigned Managed Identity
│   │   ├── Creates PostgreSQL Flexible Server
│   │   └── Creates Container App Environment
│   └── nbrly/02-configure-routing.sh <env>
│       ├── Creates backend pool
│       ├── Creates health probe
│       ├── Creates HTTP settings
│       ├── Creates HTTPS listener
│       └── Creates routing rule
└── 02-deploy-tenant-infra.sh bloom <env>
    └── (same as nbrly)
```

## Prerequisites

1. **Azure CLI** installed and authenticated
2. **jq** installed for JSON processing
3. **Configuration files** properly set up for target environment
4. **SSL certificates** available:
   - `../certs/astrapia-io-dev.pfx`
   - `../certs/astrapia-io-stage.pfx`
   - `../certs/astrapia-io-prod.pfx`
5. **Credentials file** for certificate passwords:
   - `../creds/astrapiaio.json`

## Configuration Parameters

### Common Parameters (parameters-{env}.json)

```json
{
  "env": "dev|stage|prod",
  "region": "eastus",
  "project": "astra",
  "vnetAddressPrefix": "10.x.0.0/16",
  "appGatewaySubnetPrefix": "10.x.0.0/24",
  "bastionSubnetPrefix": "10.x.1.0/26",
  "postgresSubnetPrefix": "10.x.2.0/24",
  "customDomain": {
    "certDomainName": "astrapia.io",
    "certificate": "*.astrapia.io",
    "certificateName": "astrapiaio",
    "certificateFilePath": "../certs/astrapia-io-{env}.pfx",
    "tenantDomains": {
      "nbrly": "nbrly-{env}.astrapia.io",
      "bloom": "bloom-{env}.astrapia.io"
    }
  }
}
```

### Tenant Parameters (tenants/{tenant}/parameters-{env}.json)

```json
{
  "tenantName": "nbrly|bloom",
  "caeSubnetPrefix": "10.x.y.0/24",
  "domainName": "{tenant}-{env}.astrapia.io"
}
```

## Environment Validation

All scripts validate the environment parameter:

```bash
# Valid environments
./00-deploy-all.sh dev    # ✓
./00-deploy-all.sh stage  # ✓
./00-deploy-all.sh prod   # ✓

# Invalid environments
./00-deploy-all.sh test   # ✗ Error: Invalid environment
./00-deploy-all.sh local  # ✗ Error: Invalid environment
```

## Best Practices

1. **Always specify environment** explicitly in production deployments
2. **Review configuration files** before deploying to new environment
3. **Test in dev** before deploying to stage or prod
4. **Use state files** to track deployed resources per environment
5. **Keep certificates** separate for each environment
6. **Document environment-specific settings** in configuration files

## Troubleshooting

### Configuration File Not Found

```
Error: Configuration file not found: ../config/parameters-stage.json
```

**Solution**: Create the missing configuration file based on the template.

### Invalid Environment

```
Error: Invalid environment: test
Usage: ./00-deploy-all.sh [dev|stage|prod]
```

**Solution**: Use one of the supported environments: dev, stage, or prod.

### State File Mismatch

If you see resources from wrong environment, check:
1. State file: `config/.generated/generated-infra-{env}.json`
2. Ensure you're running scripts with correct environment parameter

## Examples

### Complete Development Deployment

```bash
# Deploy everything to dev
cd scripts
./00-deploy-all.sh dev
```

### Deploy Only Common Infrastructure to Production

```bash
# Deploy shared resources to prod
cd scripts
./01-deploy-common-infra.sh prod
```

### Deploy Single Tenant to Staging

```bash
# Deploy only NBRLY tenant to stage
cd scripts
./02-deploy-tenant-infra.sh nbrly stage
```

### Update Routing for Specific Tenant

```bash
# Update Application Gateway routing for BLOOM in prod
cd scripts/bloom
./02-configure-routing.sh prod
```

## See Also

- [Configuration Guide](../config/README.md)
- [Main README](../../README.md)
- [Deployment Guide](../../docs/deployment-guide.md)
