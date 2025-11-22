# Application Gateway Routing Manifests

This directory contains the YAML manifests for configuring Application Gateway routing rules for the multi-tenant FastAPI applications.

## Directory Structure

```
routing/
├── README.md                           # This file
├── nbrly-routing.yaml                 # NBRLY tenant routing configuration
├── bloom-routing.yaml                 # BLOOM tenant routing configuration
├── application-gateway-complete.yaml  # Complete Application Gateway configuration
└── deploy-routing-yaml.sh             # Script to deploy routing using YAML
```

## Routing Configuration Overview

### NBRLY Tenant (`nbrly-dev.astrapia.io`)
- **Domain-based routing**: All traffic to `nbrly-dev.astrapia.io`
- **Path-based routing**:
  - `/app1/*` → `ca-nbrly-nbapp1-dev` (Container App)
  - `/app2/*` → `ca-nbrly-nbapp2-dev` (Container App)
  - Default (`/`) → `ca-nbrly-nbapp1-dev`

### BLOOM Tenant (`bloom-dev.astrapia.io`)
- **Domain-based routing**: All traffic to `bloom-dev.astrapia.io`
- **Path-based routing**:
  - `/app1/*` → `ca-bloom-bmapp1-dev` (Container App)
  - `/app2/*` → `ca-bloom-bmapp2-dev` (Container App)
  - Default (`/`) → `ca-bloom-bmapp1-dev`

## YAML Manifest Files

### 1. `nbrly-routing.yaml`
Contains NBRLY tenant-specific routing configuration:
- Backend address pools pointing to NBRLY Container Apps
- HTTP settings with health probe configurations
- URL path maps for `/app2/*` routing
- HTTP listener for `nbrly-dev.astrapia.io`
- Request routing rules with priority 100

### 2. `bloom-routing.yaml`
Contains BLOOM tenant-specific routing configuration:
- Backend address pools pointing to BLOOM Container Apps
- HTTP settings with health probe configurations
- URL path maps for `/app2/*` routing
- HTTP listener for `bloom-dev.astrapia.io`
- Request routing rules with priority 200

### 3. `application-gateway-complete.yaml`
Complete Application Gateway configuration including:
- **SKU Configuration**: WAF_v2 tier with 2-instance capacity
- **Network Configuration**: Subnet and public IP associations
- **Frontend Configuration**: HTTP (port 80) and HTTPS (port 443) listeners
- **Backend Pools**: All 4 Container Apps (nbrly + bloom)
- **Health Probes**: Custom probes for each application's `/health` endpoint
- **Routing Rules**: Complete multi-tenant routing setup
- **WAF Configuration**: OWASP 3.2 ruleset with Prevention mode

## Health Probe Configuration

Each application has dedicated health probes:

```yaml
probes:
  - name: probe-nbrly-app1
    protocol: Https
    path: /app1/health          # Matches FastAPI root_path
    interval: 30                # Check every 30 seconds
    timeout: 30                 # 30-second timeout
    unhealthyThreshold: 3       # 3 failures = unhealthy
    match:
      statusCodes:
        - "200-399"            # Accept 2xx and 3xx responses
```

## Backend Configuration

### HTTPS Backend Communication
- **Protocol**: HTTPS (port 443)
- **Host Header**: Picked from backend address (Container App FQDN)
- **Request Timeout**: 30 seconds
- **Health Probe**: Custom probe per application

### Dynamic FQDN Replacement
The YAML files use placeholder tokens that need to be replaced with actual Container App FQDNs:

```yaml
backendAddresses:
  - fqdn: "#{NBRLY_NBAPP1_FQDN}#"    # Replace with actual FQDN
```

## Deployment Methods

### Method 1: Using Shell Script (Recommended)
The existing `configure-routing.sh` script uses Azure CLI commands to create the same configuration:

```bash
cd ../../scripts
./configure-routing.sh
```

### Method 2: Azure CLI with YAML (Future)
Azure CLI doesn't currently support Application Gateway YAML deployment, but these files serve as:
- **Documentation**: Clear configuration specification
- **Infrastructure as Code**: Version-controlled routing definitions
- **Migration Path**: Ready for future Azure CLI YAML support

### Method 3: ARM/Bicep Templates
Convert these YAML definitions to ARM templates or Bicep files:

```bash
# Convert to ARM template (manual process)
# Use these YAML files as reference for ARM/Bicep template creation
```

## Configuration Values

### Required Substitutions
Before deployment, replace these placeholders:

```bash
# Container App FQDNs (obtained after Container App deployment)
#{NBRLY_NBAPP1_FQDN}#    # ca-nbrly-nbapp1-dev.{region}.azurecontainerapps.io
#{NBRLY_NBAPP2_FQDN}#    # ca-nbrly-nbapp2-dev.{region}.azurecontainerapps.io  
#{BLOOM_BMAPP1_FQDN}#    # ca-bloom-bmapp1-dev.{region}.azurecontainerapps.io
#{BLOOM_BMAPP2_FQDN}#    # ca-bloom-bmapp2-dev.{region}.azurecontainerapps.io

# Azure Resource IDs
{subscription-id}         # Your Azure subscription ID
```

### Get Container App FQDNs
```bash
# Get NBRLY app FQDNs
az containerapp show --name ca-nbrly-nbapp1-dev --resource-group rg-astrapia-dev --query "properties.configuration.ingress.fqdn" -o tsv
az containerapp show --name ca-nbrly-nbapp2-dev --resource-group rg-astrapia-dev --query "properties.configuration.ingress.fqdn" -o tsv

# Get BLOOM app FQDNs  
az containerapp show --name ca-bloom-bmapp1-dev --resource-group rg-astrapia-dev --query "properties.configuration.ingress.fqdn" -o tsv
az containerapp show --name ca-bloom-bmapp2-dev --resource-group rg-astrapia-dev --query "properties.configuration.ingress.fqdn" -o tsv
```

## Routing Flow

### Request Flow Diagram
```
Internet Request
        ↓
Application Gateway (agw-astrapia-dev)
        ↓
Domain-based Listener
├─ nbrly-dev.astrapia.io → listener-nbrly
└─ bloom-dev.astrapia.io → listener-bloom
        ↓
Path-based URL Map
├─ /app1/* → pool-{tenant}-app1 → Container App 1
└─ /app2/* → pool-{tenant}-app2 → Container App 2
        ↓
Backend HTTP Settings
├─ HTTPS (port 443)
├─ Health probe to /app{X}/health
└─ Host header from backend FQDN
        ↓
Container Apps (Internal Ingress)
├─ FastAPI with root_path="/app1" or "/app2"
└─ Health endpoints at configured paths
```

### URL Examples
```bash
# NBRLY Tenant
https://nbrly-dev.astrapia.io/           → ca-nbrly-nbapp1-dev (default)
https://nbrly-dev.astrapia.io/app1/      → ca-nbrly-nbapp1-dev  
https://nbrly-dev.astrapia.io/app1/docs  → ca-nbrly-nbapp1-dev/docs
https://nbrly-dev.astrapia.io/app2/      → ca-nbrly-nbapp2-dev
https://nbrly-dev.astrapia.io/app2/api/  → ca-nbrly-nbapp2-dev/api/

# BLOOM Tenant  
https://bloom-dev.astrapia.io/           → ca-bloom-bmapp1-dev (default)
https://bloom-dev.astrapia.io/app1/      → ca-bloom-bmapp1-dev
https://bloom-dev.astrapia.io/app1/docs  → ca-bloom-bmapp1-dev/docs  
https://bloom-dev.astrapia.io/app2/      → ca-bloom-bmapp2-dev
https://bloom-dev.astrapia.io/app2/api/  → ca-bloom-bmapp2-dev/api/
```

## Monitoring and Troubleshooting

### Check Backend Health
```bash
# View Application Gateway backend health
az network application-gateway show-backend-health \
  --name agw-astrapia-dev \
  --resource-group rg-astrapia-dev
```

### Test Health Probes
```bash
# Test health endpoints directly
curl -k https://ca-nbrly-nbapp1-dev.{region}.azurecontainerapps.io/app1/health
curl -k https://ca-nbrly-nbapp2-dev.{region}.azurecontainerapps.io/app2/health
curl -k https://ca-bloom-bmapp1-dev.{region}.azurecontainerapps.io/app1/health
curl -k https://ca-bloom-bmapp2-dev.{region}.azurecontainerapps.io/app2/health
```

### Debug Routing Issues
```bash
# Check Application Gateway configuration
az network application-gateway show \
  --name agw-astrapia-dev \
  --resource-group rg-astrapia-dev

# Check specific routing rule
az network application-gateway rule show \
  --gateway-name agw-astrapia-dev \
  --resource-group rg-astrapia-dev \
  --name rule-nbrly
```

## Security Configuration

### Web Application Firewall (WAF)
- **Mode**: Prevention (blocks malicious requests)
- **Rule Set**: OWASP 3.2 (latest security rules)
- **Managed Rules**: Enabled for common attack patterns
- **Custom Rules**: Can be added for tenant-specific security

### SSL/TLS Configuration
- **Frontend**: HTTP listener (can be upgraded to HTTPS)
- **Backend**: HTTPS communication to Container Apps
- **Certificates**: Custom domain certificates can be added

## Next Steps

1. **Deploy Container Apps**: Ensure all 4 Container Apps are deployed and healthy
2. **Get FQDNs**: Retrieve Container App FQDNs and update YAML placeholders
3. **Deploy Routing**: Use `configure-routing.sh` script to apply routing configuration
4. **Test Routing**: Verify domain-based and path-based routing works correctly
5. **Add SSL**: Configure custom domain certificates for HTTPS
6. **Monitor**: Set up monitoring and alerting for Application Gateway and backends