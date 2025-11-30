# HTTP Routing Configuration for Container App Environments

## Overview

This document describes the HTTP routing configuration for Azure Container Apps environments supporting multi-tenant architecture with custom domains.

## Architecture

### Environment-Level Routing

HTTP routing is configured at the **Container App Environment (CAE)** level, not at individual container app level. This allows:
- Custom domain binding to the environment
- Path-based routing to different container apps
- Shared SSL certificate across apps in the environment
- Tenant isolation through separate domains and CAEs

### Custom Domains

Each tenant has its own custom domain:
- **NBRLY**: `nbrly-dev.astrapia.io`
- **BLOOM**: `bloom-dev.astrapia.io`

### Path-Based Routing

URLs are routed to specific container apps based on path prefixes:

#### NBRLY Tenant
- `https://nbrly-dev.astrapia.io/app1` → `ca-nbrly-nbapp1-dev`
- `https://nbrly-dev.astrapia.io/app2` → `ca-nbrly-nbapp2-dev`

#### BLOOM Tenant
- `https://bloom-dev.astrapia.io/app1` → `ca-bloom-bmapp1-dev`
- `https://bloom-dev.astrapia.io/app2` → `ca-bloom-bmapp2-dev`

## Implementation

### SSL Certificate

The wildcard SSL certificate for `*.astrapia.io` is stored in Azure KeyVault:
- **KeyVault**: `astradeveastuskv`
- **Certificate Name**: `astrapiaio`
- **Secret ID**: `https://astradeveastuskv.vault.azure.net/secrets/astrapiaio/fd0d3f5a077248ea91e4e2b46b54194e`

The certificate is uploaded to each Container App Environment using the tenant's User Assigned Managed Identity for KeyVault access.

### Routing Configuration Files

#### Templates
Located in `app-gtwy-apps/manifests/routing/`:
- `nbrly-routing.yaml.template` - Template for NBRLY routing
- `bloom-routing.yaml.template` - Template for BLOOM routing

#### Generated Files
The script generates final YAML files with placeholders replaced:
- `nbrly-routing.yaml` - Applied to `nbrly-dev-cae`
- `bloom-routing.yaml` - Applied to `bloom-dev-cae`

### Configuration Script

**Location**: `app-gtwy-apps/scripts/helpers/configure-routing.sh`

**Usage**:
```bash
# Configure routing for NBRLY only
./helpers/configure-routing.sh nbrly

# Configure routing for BLOOM only
./helpers/configure-routing.sh bloom

# Configure routing for both tenants
./helpers/configure-routing.sh all
```

**What the script does**:
1. **Upload Certificate**: Uploads the SSL certificate from KeyVault to the Container App Environment
2. **Generate Routing YAML**: Creates routing configuration from template with placeholders replaced
3. **Apply Configuration**: Creates or updates HTTP route config in the CAE
4. **Verify**: Displays the applied configuration

### YAML Structure

```yaml
customDomains:
  - name: "nbrly-dev.astrapia.io"
    certificateId: "/subscriptions/.../certificates/nbrly-dev-cae-astra-dev-east-cert-1284"
    bindingType: "SniEnabled"

rules:
  - description: "NBRLY App1 routing rule"
    routes:
      - match:
          prefix: /app1
    targets:
      - containerApp: "ca-nbrly-nbapp1-dev"
```

**Key Fields**:
- `customDomains`: Custom domain bindings with SSL certificates
  - `name`: FQDN for the custom domain
  - `certificateId`: Full Azure resource ID of the certificate in the CAE
  - `bindingType`: `SniEnabled` for SNI-based HTTPS, `Auto` for managed cert, `Disabled` for HTTP only
- `rules`: Array of routing rules
  - `description`: Human-readable description
  - `routes`: Path matching rules (prefix-based)
  - `targets`: Container apps to route traffic to

## DNS Configuration

### Required DNS Records

After configuring routing, external DNS records must be configured:

#### NBRLY Tenant
```
# A Record pointing to CAE static IP
nbrly-dev.astrapia.io  →  10.100.10.190

# TXT Record for domain verification
asuid.nbrly-dev.astrapia.io  →  <verification-token>
```

#### BLOOM Tenant
```
# A Record pointing to CAE static IP
bloom-dev.astrapia.io  →  10.100.11.190

# TXT Record for domain verification
asuid.bloom-dev.astrapia.io  →  <verification-token>
```

### Get Verification Token

```bash
az containerapp env show \
  --name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg \
  --query properties.customDomainConfiguration.customDomainVerificationId \
  --output tsv
```

## Applied Configuration

### NBRLY Environment

**Status**: ✅ Configured

**HTTP Route Config**:
- **Name**: `nbrly-http-routing`
- **Custom Domain**: `nbrly-dev.astrapia.io`
- **Certificate**: `nbrly-dev-cae-astra-dev-east-cert-1284`
- **Binding Type**: SNI Enabled
- **Provisioning State**: Succeeded

**Routing Rules**:
1. `/app1` → `ca-nbrly-nbapp1-dev`
2. `/app2` → `ca-nbrly-nbapp2-dev`

**Resource ID**: `/subscriptions/984059e7-2907-4273-8569-703dddc5adfa/resourceGroups/astra-dev-eastus-rg/providers/Microsoft.App/managedEnvironments/nbrly-dev-cae/httpRouteConfigs/nbrly-http-routing`

### BLOOM Environment

**Status**: ⏳ Pending (apps not yet deployed)

Will follow same pattern as NBRLY once container apps are deployed.

## Deployment Workflow

### Prerequisites
- Container apps must be deployed to the CAE before configuring routing
- SSL certificate must exist in KeyVault
- User Assigned Managed Identity must have access to KeyVault

### Deployment Steps

1. **Deploy Container Apps** (per tenant):
   ```bash
   ./scripts/08-deploy-yaml-nbrly.sh    # For NBRLY
   ./scripts/09-deploy-yaml-bloom.sh    # For BLOOM
   ```

2. **Configure HTTP Routing**:
   ```bash
   ./scripts/helpers/configure-routing.sh all
   ```

3. **Configure DNS** (external):
   - Set A records pointing to CAE static IPs
   - Set TXT records for domain verification
   - Wait for DNS propagation

4. **Verify**:
   ```bash
   # Test routing (after DNS propagation)
   curl https://nbrly-dev.astrapia.io/app1
   curl https://nbrly-dev.astrapia.io/app2
   ```

## Troubleshooting

### Certificate Upload Issues

**Error**: Failed to upload certificate to CAE

**Solution**: 
- Verify UAMI has KeyVault secrets access
- Check certificate exists in KeyVault
- Ensure certificate is in PFX format

### Routing Configuration Failures

**Error**: Route config creation failed

**Solution**:
- Ensure container apps exist in the CAE
- Verify app names match exactly (case-sensitive)
- Check YAML syntax in template

### Custom Domain Not Working

**Symptoms**: 404 or DNS errors when accessing custom domain

**Solutions**:
1. **DNS Not Configured**:
   - Verify A record points to correct CAE static IP
   - Check TXT record for domain verification
   - Wait for DNS propagation (can take up to 48 hours)

2. **Domain Verification Pending**:
   ```bash
   az containerapp env http-route-config show \
     --name nbrly-dev-cae \
     --resource-group astra-dev-eastus-rg \
     --http-route-config-name nbrly-http-routing
   ```
   Check `provisioningState` and `provisioningErrors`

3. **Certificate Issues**:
   - Verify certificate is valid and not expired
   - Check certificate includes the custom domain
   - Ensure SNI is enabled (`bindingType: SniEnabled`)

## Azure CLI Commands Reference

### List HTTP Route Configs
```bash
az containerapp env http-route-config list \
  --name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg
```

### Show Specific Route Config
```bash
az containerapp env http-route-config show \
  --name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg \
  --http-route-config-name nbrly-http-routing
```

### Update Route Config
```bash
az containerapp env http-route-config update \
  --name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg \
  --http-route-config-name nbrly-http-routing \
  --yaml routing.yaml
```

### Delete Route Config
```bash
az containerapp env http-route-config delete \
  --name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg \
  --http-route-config-name nbrly-http-routing
```

### List Certificates in CAE
```bash
az containerapp env certificate list \
  --name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg
```

### Upload Certificate from KeyVault
```bash
az containerapp env certificate upload \
  --name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg \
  --akv-url "https://astradeveastuskv.vault.azure.net/secrets/astrapiaio/..." \
  --identity "/subscriptions/.../nbrly-dev-uami"
```

## References

- [Azure Container Apps HTTP Routing with Custom Domains](https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing-custom-domain)
- [Azure Container Apps Environment Documentation](https://learn.microsoft.com/en-us/azure/container-apps/environment)
- [Custom Domain Configuration](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates)
- [SSL/TLS Certificates in Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/certificates)

## Next Steps

1. ✅ Configure routing for NBRLY (Complete)
2. ⏳ Deploy BLOOM container apps
3. ⏳ Configure routing for BLOOM
4. ⏳ Set up DNS records for both domains
5. ⏳ Verify custom domain access
6. ⏳ Test routing rules with actual requests
