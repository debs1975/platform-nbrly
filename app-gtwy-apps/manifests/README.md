# Container Apps Deployment Manifests

This directory contains YAML manifest templates and documentation for deploying multi-tenant FastAPI applications to Azure Container Apps.

## Overview

**All generated manifests are now in `.generated/`** - this keeps templates, configuration, and generated files cleanly separated.

### Workflow
```
manifests/templates/*.yaml.template + config/*.json
    ↓ (generate-manifests.sh)
manifests/.generated/*.yaml
    ↓ (07-deploy-yaml.sh)
Azure Container Apps
```

## Directory Structure

```
manifests/                              # Templates and documentation only
├── README.md                           # This file
├── .gitignore                         # Ignores generated YAML in subdirs
├── .bak/                              # Automatic backups of generated files
│   ├── README.md                      # Backup documentation
│   └── YYYYMMDD_HHMMSS/              # Timestamped backups
│       ├── nbrly-nbapp1.yaml
│       ├── nbrly-nbapp2.yaml
│       ├── bloom-bmapp1.yaml
│       └── bloom-bmapp2.yaml
├── .generated/                        # Generated manifests (git-ignored)
│   ├── .gitignore                     # Ignores all *.yaml files
│   ├── README.md                      # Generation documentation
│   ├── nbrly-nbapp1.yaml              # Generated from basic template
│   ├── nbrly-nbapp2.yaml              # Generated from database template
│   ├── bloom-bmapp1.yaml              # Generated from basic template
│   ├── bloom-bmapp2.yaml              # Generated from database template
│   └── routing/                       # Generated routing configs
│       ├── nbrly-routing.yaml
│       ├── bloom-routing.yaml
│       └── application-gateway-complete.yaml
├── templates/                          # Template files (committed to git)
│   ├── README.md                      # Template documentation
│   ├── containerapp-basic.yaml.template
│   └── containerapp-with-database.yaml.template
└── routing/                           # Routing documentation
    └── README.md                      # Routing configuration docs
```

**Important**: 
- `manifests/templates/`: Committed to git (source of truth for structure)
- `manifests/.generated/`: All generated YAML files (git-ignored, regenerated on each deployment)
- `manifests/.bak/`: Automatic backups before regeneration (git-ignored)
- Configuration files (`config/`): Committed to git (source of truth for values)

## Manifest Generation

### Automatic Generation (Recommended)
Manifests are automatically generated when deploying:
```bash
cd ../scripts
./07-deploy-yaml.sh [TAG]
```

The deployment script:
1. Generates manifests from templates using `scripts/helpers/generate-manifests.sh`
2. Replaces configuration values from `config/parameters-dev.json` and tenant configs
3. Fetches UAMI client IDs from Azure
4. Deploys the generated manifests

### Manual Generation
To generate manifests without deploying:
```bash
cd ../scripts/helpers
./generate-manifests.sh
```

This creates all 4 Container App manifests in `manifests/.generated/`.

**Note**: Existing manifests are automatically backed up to `manifests/.bak/<timestamp>/` before new ones are generated.

### Manifest Backups

Before generating new manifests, the system automatically backs up existing ones:

- **Backup Location**: `manifests/.bak/<timestamp>/`
- **Timestamp Format**: `YYYYMMDD_HHMMSS` (e.g., `20251122_143025`)
- **Contents**: Complete copy of all existing manifests organized by tenant

**Restoring from backup**:
```bash
# List available backups
ls -lt manifests/.bak/

# Restore specific backup (if needed)
cp -r manifests/.bak/20251122_143025/*.yaml manifests/.generated/
```

See [.bak/README.md](.bak/README.md) for detailed backup documentation.

### Template System
See [templates/README.md](templates/README.md) for detailed documentation on:
- Available templates
- Placeholder syntax and values
- Adding new templates
- Template best practices

## Container Apps Configuration

### Common Configuration
All Container Apps share these common settings:
- **Container App Environment**: `astra-dev-eastus-cae`
- **Resource Group**: `astra-dev-eastus-rg`
- **Container Registry**: `astradevacr.azurecr.io`
- **Authentication**: User-assigned managed identity (tenant-specific)
  - **NBRLY**: `nbrly-dev-uami`
  - **BLOOM**: `bloom-dev-uami`
- **Key Vault**: `astradeveastuskv` (for database secrets in *app2)
- **Ingress**: Internal only (no external access)
- **Port**: 8000
- **Protocol**: HTTP
- **CPU**: 0.5 cores
- **Memory**: 1Gi
- **Min Replicas**: 1
- **Max Replicas**: 3

### Health Probes
Each Container App includes:
- **Liveness Probe**: `GET /health/live` (30s initial delay, 10s period)
- **Readiness Probe**: `GET /health/ready` (5s initial delay, 5s period)

### Auto-scaling
HTTP-based scaling triggers when concurrent requests exceed 100.

## Deployment Methods

### Method 1: YAML Deployment with Template Generation (Recommended)

The automated deployment script handles everything:
```bash
cd ../scripts
./07-deploy-yaml.sh [TAG]
```

This will:
1. **Generate manifests** from templates using configuration files
2. **Fetch UAMI client IDs** from Azure
3. **Replace placeholders** in generated manifests
4. **Deploy** Container Apps using Azure CLI

Manual step-by-step (for learning purposes):
```bash
# 1. Generate manifests from templates
cd ../scripts/helpers
./generate-manifests.sh

# 2. Deploy using Azure CLI
cd ../../manifests
az containerapp create --resource-group rg-astrapia-dev --yaml nbrly/nbapp1-containerapp.yaml
az containerapp create --resource-group rg-astrapia-dev --yaml nbrly/nbapp2-containerapp.yaml
az containerapp create --resource-group rg-astrapia-dev --yaml bloom/bmapp1-containerapp.yaml
az containerapp create --resource-group rg-astrapia-dev --yaml bloom/bmapp2-containerapp.yaml
```

**Note**: Manual deployment requires UAMI client IDs to be populated in the manifests.

### Method 2: Imperative Scripts (Alternative)
```bash
# Use the shell scripts which programmatically create the same configuration
cd ../scripts
./04-deploy-all.sh latest
```

## Environment Variables

Each Container App is configured with tenant-specific environment variables:

### NBRLY Tenant
```yaml
env:
  - name: ENVIRONMENT
    value: "dev"
  - name: ROOT_PATH
    value: "/app1" # or "/app2"
  - name: APP_NAME
    value: "NBRLY-NBAPP1" # or "NBRLY-NBAPP2"
  - name: TENANT
    value: "nbrly"
  - name: APP_TYPE
    value: "nbapp1" # or "nbapp2"
  - name: AZURE_CLIENT_ID
    value: "#{NBRLY_UAMI_CLIENT_ID}#"  # Replaced by deploy script
  - name: DATABASE_URL  # nbapp2 only
    secretRef: db-connection-string
```

### BLOOM Tenant
```yaml
env:
  - name: ENVIRONMENT
    value: "dev"
  - name: ROOT_PATH
    value: "/app1" # or "/app2"
  - name: APP_NAME
    value: "BLOOM-BMAPP1" # or "BLOOM-BMAPP2"
  - name: TENANT
    value: "bloom"
  - name: APP_TYPE
    value: "bmapp1" # or "bmapp2"
  - name: AZURE_CLIENT_ID
    value: "#{BLOOM_UAMI_CLIENT_ID}#"  # Replaced by deploy script
  - name: DATABASE_URL  # bmapp2 only
    secretRef: db-connection-string
```

## Prerequisites

Before deploying these manifests:

1. **Infrastructure deployed via iac-cli**:
   ```bash
   cd ../scripts
   ./00-deploy-all.sh
   ```

2. **Azure Container App Environment** must exist:
   ```bash
   az containerapp env show --name astra-dev-eastus-cae --resource-group astra-dev-eastus-rg
   ```

3. **Azure Container Registry** with images:
   ```bash
   az acr repository list --name astradevacr
   ```

4. **User Assigned Managed Identities** with proper permissions:
   ```bash
   # Verify NBRLY UAMI
   az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg
   
   # Verify BLOOM UAMI
   az identity show --name bloom-dev-uami --resource-group astra-dev-eastus-rg
   ```

5. **UAMI client IDs populated** in configuration:
   ```bash
   cd ../app-gtwy-apps/scripts/helpers
   ./populate-uami-ids.sh
   ```

## Updating Manifests

### Change Image Tag
Update the `image` field in each manifest:
```yaml
image: astradevacr.azurecr.io/nbrly-nbapp1:v1.2.3
```

### Update Resources
Modify CPU and memory allocation:
```yaml
resources:
  cpu: 1.0      # Increase CPU
  memory: 2Gi   # Increase memory
```

### Modify Scaling
Adjust auto-scaling parameters:
```yaml
scale:
  minReplicas: 2        # Minimum instances
  maxReplicas: 10       # Maximum instances
  rules:
    - name: http-scaling
      http:
        metadata:
          concurrentRequests: "50"  # Lower threshold
```

## Monitoring and Troubleshooting

### Check Container App Status
```bash
az containerapp show --name ca-nbrly-nbapp1-dev --resource-group rg-astrapia-dev
```

### View Logs
```bash
az containerapp logs show --name ca-nbrly-nbapp1-dev --resource-group rg-astrapia-dev --follow
```

### Check Health Probes
```bash
# Get the Container App FQDN
FQDN=$(az containerapp show --name ca-nbrly-nbapp1-dev --resource-group rg-astrapia-dev --query "properties.configuration.ingress.fqdn" -o tsv)

# Test health endpoints
curl https://$FQDN/health
curl https://$FQDN/health/ready
curl https://$FQDN/health/live
```

### Scale Manually
```bash
az containerapp update --name ca-nbrly-nbapp1-dev --resource-group rg-astrapia-dev --min-replicas 2 --max-replicas 5
```

## Advanced Configuration

### Adding Secrets
To add secrets (e.g., database connection strings):
```yaml
configuration:
  secrets:
    - name: database-connection-string
      keyVaultUrl: https://your-keyvault.vault.azure.net/secrets/db-connection
      identity: system
```

### Adding Volume Mounts
For persistent storage:
```yaml
template:
  volumes:
    - name: shared-data
      storageType: AzureFile
      storageName: shared-storage
  containers:
    - name: app
      volumeMounts:
        - mountPath: /data
          volumeName: shared-data
```

### Custom Domains (via Application Gateway)
These Container Apps use internal ingress. External access is provided through Application Gateway routing configured in `../scripts/08-configure-routing.sh`.

## Security Considerations

- **Internal Ingress**: Container Apps are not directly accessible from the internet
- **User Assigned Managed Identity**: Each tenant has dedicated UAMI for secure authentication
  - **ACR Pull**: No passwords required for image pulls
  - **Key Vault Access**: Secure secret retrieval without credentials
- **Tenant Isolation**: Separate UAMIs ensure tenant-specific access control
- **No Secrets in YAML**: Database connection strings stored in Azure Key Vault
- **Resource Limits**: CPU and memory limits prevent resource exhaustion
- **Health Probes**: Ensure only healthy instances receive traffic

## Managed Identity Integration

### Identity Configuration
Each manifest specifies the tenant's User Assigned Managed Identity:

```yaml
identity:
  type: UserAssigned
  userAssignedIdentities:
    /subscriptions/{subscription-id}/resourceGroups/astra-dev-eastus-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/nbrly-dev-uami: {}
```

### ACR Authentication
```yaml
configuration:
  registries:
    - server: astradevacr.azurecr.io
      identity: /subscriptions/{subscription-id}/resourceGroups/astra-dev-eastus-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/nbrly-dev-uami
```

### Key Vault Secrets (for *app2)
```yaml
configuration:
  secrets:
    - name: db-connection-string
      keyVaultUrl: https://astradeveastuskv.vault.azure.net/secrets/nbrly-psql-connection-string
      identity: /subscriptions/{subscription-id}/resourceGroups/astra-dev-eastus-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/nbrly-dev-uami
```

## Next Steps

1. **Deploy Infrastructure**: Ensure Container App Environment exists
2. **Build Images**: Use `../scripts/build-push-all.sh` to create images
3. **Deploy Apps**: Use these YAML manifests or deployment scripts
4. **Configure Routing**: Use `../scripts/08-configure-routing.sh` for Application Gateway
5. **Test Access**: Verify routing through Application Gateway domains