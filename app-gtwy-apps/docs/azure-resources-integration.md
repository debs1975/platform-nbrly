# Azure Resources Integration Guide

This document describes how `app-gtwy-apps` integrates with Azure infrastructure resources created by the `iac-cli` deployment scripts.

## Overview

The `app-gtwy-apps` deployment system uses Azure infrastructure resources provisioned by `iac-cli` to enable secure, production-ready multi-tenant applications. The key integration points are:

1. **User Assigned Managed Identities (UAMI)** - For secure ACR authentication and Key Vault access
2. **Azure Key Vault** - For secure secret management (database connection strings)
3. **Azure Container Registry (ACR)** - For Docker image storage
4. **PostgreSQL Flexible Servers** - For tenant databases
5. **Log Analytics Workspace** - For monitoring and logging

## Infrastructure Resources

### Common Resources (Shared across tenants)

Created by: `iac-cli/scripts/01-deploy-common-infra.sh`

| Resource Type | Resource Name | Purpose |
|--------------|---------------|---------|
| Resource Group | `astra-dev-eastus-rg` | Container for all resources |
| Virtual Network | `astra-dev-eastus-vnet` | Network isolation |
| Application Gateway | `astra-dev-eastus-appgtwy` | Ingress controller and SSL termination |
| Azure Container Registry | `astradevacr` | Docker image repository |
| Azure Key Vault | `astradeveastuskv` | Secret storage |
| Log Analytics Workspace | `astra-dev-eastus-law` | Centralized logging |
| Container App Environment | `astra-dev-eastus-cae` | Shared environment for container apps |

### Tenant-Specific Resources

Created by: `iac-cli/scripts/{tenant}/01-deploy-tenant-resources.sh`

#### NBRLY Tenant

| Resource Type | Resource Name | Purpose |
|--------------|---------------|---------|
| User Managed Identity | `nbrly-dev-uami` | ACR pull + Key Vault access |
| PostgreSQL Flexible Server | `nbrly-dev-psql` | NBRLY database |
| Database Secret (Key Vault) | `nbrly-psql-connection-string` | Secure connection string |

#### BLOOM Tenant

| Resource Type | Resource Name | Purpose |
|--------------|---------------|---------|
| User Managed Identity | `bloom-dev-uami` | ACR pull + Key Vault access |
| PostgreSQL Flexible Server | `bloom-dev-psql` | BLOOM database |
| Database Secret (Key Vault) | `bloom-psql-connection-string` | Secure connection string |

## Managed Identity Integration

### Purpose

User Assigned Managed Identities (UAMI) provide secure, credential-free authentication for:
- **ACR Pull**: Container Apps pull images from ACR without passwords
- **Key Vault Access**: Container Apps retrieve secrets without storing credentials

### Implementation

#### 1. UAMI Creation (iac-cli)

```bash
# Created in iac-cli/scripts/{tenant}/01-deploy-tenant-resources.sh
uamiName="${tenantName}-${env}-uami"
az identity create \
    --name "$uamiName" \
    --resource-group "$resourceGroup"

# Assign AcrPull role
az role assignment create \
    --assignee "$uamiPrincipalId" \
    --role "AcrPull" \
    --scope "$acrId"
```

#### 2. UAMI Configuration (app-gtwy-apps)

Configuration files reference the UAMI:

**`app-gtwy-apps/config/nbrly/parameters-dev.json`**:
```json
{
  "managedIdentity": {
    "name": "nbrly-dev-uami",
    "resourceId": "/subscriptions/.../resourceGroups/astra-dev-eastus-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/nbrly-dev-uami",
    "clientId": "#{NBRLY_UAMI_CLIENT_ID}#",
    "principalId": "#{NBRLY_UAMI_PRINCIPAL_ID}#"
  }
}
```

#### 3. UAMI ID Population

Before deployment, run the helper script to populate actual IDs:

```bash
cd app-gtwy-apps/scripts/helpers
./populate-uami-ids.sh
```

This script:
- Queries Azure for each tenant's UAMI
- Retrieves `clientId`, `principalId`, and `resourceId`
- Updates tenant configuration files with actual values
- Updates `AZURE_CLIENT_ID` environment variables in application configs

#### 4. Container App Deployment with UAMI

**`app-gtwy-apps/scripts/deploy-nbrly.sh`**:
```bash
# Read UAMI configuration
uami_name=$(get_tenant_value "$TENANT" "$ENV" ".managedIdentity.name")
uami_resource_id=$(get_tenant_value "$TENANT" "$ENV" ".managedIdentity.resourceId")

# Create container app with managed identity
az containerapp create \
    --name "$app_name" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$CONTAINER_APP_ENV" \
    --image "$image_repo:$TAG" \
    --registry-server "$ACR_REGISTRY" \
    --registry-identity "$uami_resource_id" \  # Use UAMI for ACR pull
    --user-assigned "$uami_resource_id" \      # Assign UAMI to container app
    ...
```

## Key Vault Integration

### Purpose

Azure Key Vault stores sensitive secrets (database connection strings) that are injected into Container Apps at runtime.

### Implementation

#### 1. Secret Storage (iac-cli)

```bash
# Created in iac-cli/scripts/{tenant}/02-deploy-databases.sh
az keyvault secret set \
    --vault-name "$keyVaultName" \
    --name "nbrly-psql-connection-string" \
    --value "postgresql://user:pass@server/db"
```

#### 2. Key Vault Configuration (app-gtwy-apps)

**`app-gtwy-apps/config/parameters-dev.json`**:
```json
{
  "keyVault": {
    "name": "astradeveastuskv",
    "secrets": {
      "nbrlyDatabase": "nbrly-psql-connection-string",
      "bloomDatabase": "bloom-psql-connection-string"
    }
  }
}
```

**`app-gtwy-apps/config/nbrly/parameters-dev.json`**:
```json
{
  "database": {
    "serverName": "nbrly-dev-psql",
    "databaseName": "nbrlydb",
    "connectionStringSecret": "nbrly-psql-connection-string"
  }
}
```

#### 3. Secret Injection into Container Apps

For database-enabled applications (nbapp2, bmapp2):

```bash
# Add Key Vault secret reference
kv_name=$(get_global_value "$ENV" ".keyVault.name")
db_secret=$(get_tenant_value "$TENANT" "$ENV" ".database.connectionStringSecret")

az containerapp secret set \
    --name "$app_name" \
    --resource-group "$RESOURCE_GROUP" \
    --secrets "db-connection-string=keyvaultref:https://${kv_name}.vault.azure.net/secrets/${db_secret},identityref:$uami_resource_id"

# Use secret in environment variable
az containerapp update \
    --name "$app_name" \
    --resource-group "$RESOURCE_GROUP" \
    --set-env-vars "DATABASE_URL=secretref:db-connection-string"
```

### Key Vault Access Policy

The UAMI must have "Get" permission on secrets:

```bash
# Set in iac-cli
az keyvault set-policy \
    --name "$keyVaultName" \
    --object-id "$uamiPrincipalId" \
    --secret-permissions get
```

## Application Configuration

### Environment Variables

Container Apps receive these environment variables:

| Variable | Source | Purpose |
|----------|--------|---------|
| `ENVIRONMENT` | Configuration | Deployment environment (dev/staging/prod) |
| `ROOT_PATH` | Configuration | API root path for routing |
| `APP_NAME` | Configuration | Container app name |
| `TENANT` | Configuration | Tenant identifier (nbrly/bloom) |
| `AZURE_CLIENT_ID` | UAMI | Managed identity client ID |
| `DATABASE_URL` | Key Vault Secret | Database connection string (for *app2) |

### Application Code Example

**Using Managed Identity in Python (FastAPI)**:

```python
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
import os

# Initialize managed identity credential
credential = ManagedIdentityCredential(
    client_id=os.getenv("AZURE_CLIENT_ID")
)

# Access Key Vault
vault_url = "https://astradeveastuskv.vault.azure.net"
secret_client = SecretClient(vault_url=vault_url, credential=credential)

# Retrieve secret
db_connection = secret_client.get_secret("nbrly-psql-connection-string").value
```

**Using Database Connection (injected via Key Vault)**:

```python
import os
from sqlalchemy import create_engine

# DATABASE_URL is automatically injected from Key Vault
database_url = os.getenv("DATABASE_URL")
engine = create_engine(database_url)
```

## Deployment Workflow

### Prerequisites

1. Deploy infrastructure using `iac-cli`:
   ```bash
   cd iac-cli/scripts
   ./00-deploy-all.sh
   ```

2. Verify resources in `iac-cli/config/.generated/generated-infra-dev.json`

### Deployment Steps

1. **Populate UAMI IDs**:
   ```bash
   cd app-gtwy-apps/scripts/helpers
   ./populate-uami-ids.sh
   ```

2. **Build and push images to ACR**:
   ```bash
   cd app-gtwy-apps/scripts
   ./build-push-all.sh
   ```

3. **Deploy container apps**:
   ```bash
   ./deploy-all.sh
   ```

4. **Configure Application Gateway routing**:
   ```bash
   ./configure-routing.sh
   ```

### Verification

1. **Verify UAMI has ACR access**:
   ```bash
   az role assignment list \
       --assignee $(az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg --query principalId -o tsv) \
       --scope /subscriptions/.../resourceGroups/astra-dev-eastus-rg/providers/Microsoft.ContainerRegistry/registries/astradevacr
   ```

2. **Verify Key Vault access policy**:
   ```bash
   az keyvault show \
       --name astradeveastuskv \
       --query "properties.accessPolicies[?objectId=='<uami-principal-id>']"
   ```

3. **Test Container App**:
   ```bash
   # Get Container App FQDN
   fqdn=$(az containerapp show --name ca-nbrly-nbapp1-dev --resource-group astra-dev-eastus-rg --query "properties.configuration.ingress.fqdn" -o tsv)
   
   # Test health endpoint
   curl https://$fqdn/health
   ```

## Security Considerations

### Managed Identity Benefits

- **No credentials in code**: Applications never store ACR or Key Vault credentials
- **Automatic rotation**: Azure handles credential rotation automatically
- **Principle of least privilege**: Each tenant has its own UAMI with minimal required permissions
- **Audit trail**: All access is logged in Azure Activity Log

### Key Vault Best Practices

- **Secret versioning**: Key Vault maintains secret versions
- **Access policies**: Only specific UAMIs can access specific secrets
- **Secret references**: Secrets are never stored in configuration files
- **Audit logging**: All secret access is logged

### Network Security

- **Internal ingress**: Container Apps are not publicly accessible
- **Application Gateway**: Single public entry point with SSL termination
- **VNet integration**: All resources communicate over private network
- **NSG rules**: Network security groups control traffic flow

## Troubleshooting

### UAMI Not Found

**Error**: `Managed identity not found`

**Solution**:
1. Verify UAMI exists: `az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg`
2. Run `populate-uami-ids.sh` to update configuration
3. Check resource group name matches

### ACR Pull Failed

**Error**: `Failed to pull image from ACR`

**Solution**:
1. Verify AcrPull role assignment:
   ```bash
   az role assignment list --assignee <uami-principal-id> --scope <acr-resource-id>
   ```
2. Re-assign role if missing:
   ```bash
   az role assignment create --assignee <uami-principal-id> --role AcrPull --scope <acr-resource-id>
   ```

### Key Vault Access Denied

**Error**: `Access denied to Key Vault secret`

**Solution**:
1. Verify access policy:
   ```bash
   az keyvault show --name astradeveastuskv --query "properties.accessPolicies"
   ```
2. Set policy if missing:
   ```bash
   az keyvault set-policy \
       --name astradeveastuskv \
       --object-id <uami-principal-id> \
       --secret-permissions get
   ```

### AZURE_CLIENT_ID Not Set

**Error**: `AZURE_CLIENT_ID environment variable not found`

**Solution**:
1. Run `populate-uami-ids.sh` to update configuration
2. Verify configuration file has correct `clientId`
3. Redeploy container app

## References

- [Azure Managed Identities Documentation](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Azure Key Vault Secret References in Container Apps](https://learn.microsoft.com/azure/container-apps/manage-secrets)
- [Azure Container Registry Authentication with Managed Identity](https://learn.microsoft.com/azure/container-registry/container-registry-authentication-managed-identity)
- [Securing secrets in Container Apps](https://learn.microsoft.com/azure/container-apps/manage-secrets?tabs=azure-cli)

## Configuration Files Reference

### Global Configuration
- `app-gtwy-apps/config/parameters-dev.json` - Shared infrastructure resources

### Tenant Configurations
- `app-gtwy-apps/config/nbrly/parameters-dev.json` - NBRLY tenant resources
- `app-gtwy-apps/config/bloom/parameters-dev.json` - BLOOM tenant resources

### Generated Infrastructure
- `iac-cli/config/.generated/generated-infra-dev.json` - Actual deployed resource names and IDs

### Scripts
- `app-gtwy-apps/scripts/helpers/populate-uami-ids.sh` - Populate UAMI IDs from Azure
- `app-gtwy-apps/scripts/deploy-nbrly.sh` - Deploy NBRLY apps with managed identity
- `app-gtwy-apps/scripts/deploy-bloom.sh` - Deploy BLOOM apps with managed identity
