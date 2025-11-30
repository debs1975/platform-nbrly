# Hostname/FQDN Configuration Guide

## Overview

This document explains where and how tenant hostnames (FQDNs) are configured and used throughout the multi-tenant Azure infrastructure.

## Hostname Format

The hostnames follow the pattern: `<tenant>-<environment>.astrapia.io`

- **NBRLY Tenant (dev)**: `nbrly-dev.astrapia.io`
- **BLOOM Tenant (dev)**: `bloom-dev.astrapia.io`

## Configuration Locations

### 1. Infrastructure Configuration (Source of Truth)

**File**: `config/infra-dev.json`

The infrastructure configuration contains the authoritative hostname values under the tenant resources:

```json
{
  "resources": {
    "tenants": {
      "nbrly": {
        "hostName": "nbrly-dev.astrapia.io",
        ...
      },
      "bloom": {
        "hostName": "bloom-dev.astrapia.io",
        ...
      }
    }
  }
}
```

**Access in scripts**:
```bash
NBRLY_DOMAIN=$(get_infra_value "$ENV" ".resources.tenants.nbrly.hostName")
BLOOM_DOMAIN=$(get_infra_value "$ENV" ".resources.tenants.bloom.hostName")
```

### 2. Global Parameters (Alternative Reference)

**File**: `config/parameters-dev.json`

Also contains tenant domains for convenience:

```json
{
  "customDomain": {
    "tenantDomains": {
      "nbrly": "nbrly-dev.astrapia.io",
      "bloom": "bloom-dev.astrapia.io"
    }
  }
}
```

### 3. Tenant-Specific Configuration (Convenience Copy)

**Files**: 
- `config/nbrly/parameters-dev.json`
- `config/bloom/parameters-dev.json`

Each tenant config includes its own domain for easy reference:

```json
{
  "tenantName": "nbrly",
  "domainName": "nbrly-dev.astrapia.io",
  ...
}
```

**Access in scripts**:
```bash
NBRLY_DOMAIN=$(get_tenant_value "nbrly" "$ENV" ".domainName")
```

## Usage in Scripts

### Recommended Approach (Infrastructure Config)

For scripts that work with multiple tenants or infrastructure-level operations:

```bash
# Load from infrastructure config
NBRLY_DOMAIN=$(get_infra_value "$ENV" ".resources.tenants.nbrly.hostName")
BLOOM_DOMAIN=$(get_infra_value "$ENV" ".resources.tenants.bloom.hostName")
```

**Examples**:
- `scripts/08-configure-routing.sh` - Application Gateway routing
- `scripts/routing/configure-routing-*.sh` - Routing configuration

### Alternative Approach (Tenant Config)

For tenant-specific operations:

```bash
# Load from tenant config
TENANT_DOMAIN=$(get_tenant_value "nbrly" "$ENV" ".domainName")
```

**Examples**:
- Tenant-specific deployment scripts
- Single-tenant configuration operations

## Application Gateway Integration

The hostnames are used in Application Gateway configuration for:

### 1. HTTP Listeners

Each tenant has a dedicated HTTP listener that routes traffic based on the hostname:

```bash
az network application-gateway http-listener create \
    --name "listener-nbrly" \
    --host-name "nbrly-dev.astrapia.io"
```

### 2. Routing Rules

Domain-based routing directs traffic to the appropriate tenant's Container App Environment:

- `https://nbrly-dev.astrapia.io/*` → NBRLY Container Apps
- `https://bloom-dev.astrapia.io/*` → BLOOM Container Apps

### 3. Path-Based Routing

Combined with path-based routing for specific applications:

- `https://nbrly-dev.astrapia.io/app1/*` → ca-nbrly-nbapp1-dev
- `https://nbrly-dev.astrapia.io/app2/*` → ca-nbrly-nbapp2-dev
- `https://bloom-dev.astrapia.io/app1/*` → ca-bloom-bmapp1-dev
- `https://bloom-dev.astrapia.io/app2/*` → ca-bloom-bmapp2-dev

## DNS Configuration

DNS records must be configured to point the hostnames to the Application Gateway's public IP:

```
nbrly-dev.astrapia.io   →  A Record  →  20.42.50.96 (Application Gateway)
bloom-dev.astrapia.io   →  A Record  →  20.42.50.96 (Application Gateway)
```

Both hostnames point to the same Application Gateway, which handles tenant routing based on the hostname in the request.

## SSL/TLS Certificate

A wildcard certificate is used to cover all tenant subdomains:

- **Certificate**: `*.astrapia.io`
- **Key Vault**: `astradeveastuskv`
- **Certificate Name**: `astrapiaio`

This single certificate supports:
- `nbrly-dev.astrapia.io`
- `bloom-dev.astrapia.io`
- Any future tenant: `<tenant>-dev.astrapia.io`

## Configuration Consistency

To ensure all configuration files stay in sync:

1. **Update infrastructure config first** (`infra-dev.json`)
   - This is the source of truth for hostnames

2. **Update global parameters** (`parameters-dev.json`)
   - Keep `customDomain.tenantDomains` in sync

3. **Update tenant configs** (`<tenant>/parameters-dev.json`)
   - Keep each tenant's `domainName` field in sync

### Validation Script

Run the configuration validator to ensure consistency:

```bash
cd scripts/helpers
./config-loader.sh validate dev
```

This will check all configuration files for:
- Valid JSON syntax
- Required fields present
- Cross-file consistency (future enhancement)

## Testing Hostname Configuration

### 1. Test Config Loading

```bash
cd scripts/helpers
./config-loader.sh summary dev
```

This displays all configuration values including hostnames.

### 2. Test Application Gateway Routing

```bash
cd scripts
./08-configure-routing.sh
```

This will configure Application Gateway with the hostnames and report any issues.

### 3. Test DNS Resolution

```bash
# Test DNS resolution
nslookup nbrly-dev.astrapia.io
nslookup bloom-dev.astrapia.io

# Should both resolve to: 20.42.50.96
```

### 4. Test End-to-End Access

```bash
# Test NBRLY tenant
curl -I https://nbrly-dev.astrapia.io/app1/health
curl -I https://nbrly-dev.astrapia.io/app2/health

# Test BLOOM tenant
curl -I https://bloom-dev.astrapia.io/app1/health
curl -I https://bloom-dev.astrapia.io/app2/health
```

## Troubleshooting

### Hostname Not Loading Correctly

**Symptom**: Scripts show empty or "null" for domain values

**Solution**:
1. Verify `infra-dev.json` has the correct path:
   ```bash
   jq '.resources.tenants.nbrly.hostName' config/infra-dev.json
   ```

2. Check tenant config files:
   ```bash
   jq '.domainName' config/nbrly/parameters-dev.json
   ```

3. Ensure consistent values across all config files

### Application Gateway Not Routing Correctly

**Symptom**: 404 errors or incorrect routing

**Solution**:
1. Verify HTTP listeners are configured with correct hostnames:
   ```bash
   az network application-gateway http-listener list \
       --gateway-name astra-dev-eastus-agw \
       --resource-group astra-dev-eastus-rg \
       --query "[].{name:name, hostName:hostNames}" -o table
   ```

2. Check routing rules:
   ```bash
   az network application-gateway rule list \
       --gateway-name astra-dev-eastus-agw \
       --resource-group astra-dev-eastus-rg -o table
   ```

3. Reconfigure routing:
   ```bash
   cd scripts
   ./08-configure-routing.sh
   ```

### DNS Not Resolving

**Symptom**: `nslookup` fails to resolve hostnames

**Solution**:
1. Verify DNS records are configured in your DNS provider
2. Check Application Gateway public IP:
   ```bash
   az network public-ip show \
       --name astra-dev-eastus-pip \
       --resource-group astra-dev-eastus-rg \
       --query ipAddress -o tsv
   ```
3. Ensure DNS A records point to the correct IP (20.42.50.96)

## Best Practices

1. **Single Source of Truth**: Always treat `infra-dev.json` as the authoritative source for hostnames

2. **Consistency**: When updating hostnames, update all three locations:
   - `infra-dev.json`
   - `parameters-dev.json`
   - `<tenant>/parameters-dev.json`

3. **Environment Separation**: Use different hostnames for different environments:
   - Dev: `<tenant>-dev.astrapia.io`
   - Staging: `<tenant>-staging.astrapia.io`
   - Prod: `<tenant>.astrapia.io`

4. **Wildcard Certificate**: Use wildcard certificates (`*.astrapia.io`) to support all tenants with a single certificate

5. **DNS Management**: Centralize DNS management and use infrastructure-as-code (Terraform/Bicep) to manage DNS records

## Summary

- **Format**: `<tenant>-<environment>.astrapia.io`
- **NBRLY**: `nbrly-dev.astrapia.io`
- **BLOOM**: `bloom-dev.astrapia.io`
- **Source of Truth**: `config/infra-dev.json` → `.resources.tenants.<tenant>.hostName`
- **Scripts Use**: `get_infra_value "$ENV" ".resources.tenants.<tenant>.hostName"`
- **DNS**: Both point to Application Gateway IP: 20.42.50.96
- **Certificate**: Wildcard `*.astrapia.io` covers all tenants
- **Routing**: Application Gateway uses hostname-based routing + path-based routing
