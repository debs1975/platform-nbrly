# Container App Manifest Templates

This directory contains YAML templates for generating Container App manifests. Templates use placeholder syntax `#{PLACEHOLDER}#` which are replaced with actual values from configuration files during manifest generation.

## Templates

### containerapp-basic.yaml.template
Template for Container Apps without database connections.

**Used by:**
- `nbapp1` (NBRLY tenant)
- `bmapp1` (BLOOM tenant)

**Features:**
- User Assigned Managed Identity
- ACR authentication via UAMI
- Basic health probes (liveness, readiness, startup)
- Configurable CPU, memory, and replica settings

### containerapp-with-database.yaml.template
Template for Container Apps with PostgreSQL database connections.

**Used by:**
- `nbapp2` (NBRLY tenant)
- `bmapp2` (BLOOM tenant)

**Features:**
- All features from basic template
- Key Vault secret integration for database connection strings
- DATABASE_URL environment variable with secretRef

## Available Placeholders

### Global Placeholders (from config/parameters-dev.json)
- `#{SUBSCRIPTION_ID}#` - Azure subscription ID
- `#{RESOURCE_GROUP}#` - Azure resource group name
- `#{LOCATION}#` - Azure region
- `#{ENVIRONMENT}#` - Environment name (dev, staging, prod)
- `#{ACR_REGISTRY}#` - Azure Container Registry name
- `#{KEY_VAULT_NAME}#` - Azure Key Vault name

### Tenant Placeholders (from config/nbrly|bloom/parameters-dev.json)
- `#{TENANT}#` - Tenant identifier (nbrly, bloom)
- `#{CONTAINER_APP_ENV}#` - Container Apps Environment resource ID
- `#{UAMI_NAME}#` - User Assigned Managed Identity name
- `#{UAMI_RESOURCE_ID}#` - UAMI full resource ID
- `#{DB_SECRET_NAME}#` - Key Vault secret name for database connection

### App-Specific Placeholders (from app configuration)
- `#{APP_NAME}#` - Full Container App name (e.g., ca-nbrly-nbapp1-dev)
- `#{APP_KEY}#` - App identifier (nbapp1, nbapp2, bmapp1, bmapp2)
- `#{APP_TYPE}#` - Same as APP_KEY
- `#{IMAGE_NAME}#` - Docker image name (tenant/app)
- `#{IMAGE_TAG}#` - Docker image tag
- `#{ROOT_PATH}#` - API root path (e.g., /app1)
- `#{CPU}#` - CPU allocation (e.g., 0.5)
- `#{MEMORY}#` - Memory allocation (e.g., 1.0Gi)
- `#{MIN_REPLICAS}#` - Minimum replica count
- `#{MAX_REPLICAS}#` - Maximum replica count

### Runtime Placeholders (populated at deployment)
- `#{NBRLY_UAMI_CLIENT_ID}#` - NBRLY UAMI client ID (fetched from Azure)
- `#{BLOOM_UAMI_CLIENT_ID}#` - BLOOM UAMI client ID (fetched from Azure)

## Manifest Generation

### Automatic Generation
Manifests are automatically generated from templates when running:
```bash
./scripts/deploy-yaml.sh
```

The deployment script:
1. Calls `scripts/helpers/generate-manifests.sh`
2. Generates all 4 manifests from templates
3. Fetches UAMI client IDs from Azure
4. Replaces client ID placeholders
5. Deploys the manifests

### Manual Generation
To generate manifests without deploying:
```bash
./scripts/helpers/generate-manifests.sh
```

This will:
- Read configuration from `config/parameters-dev.json` and tenant-specific configs
- Process all templates
- Generate manifests in:
  - `manifests/nbrly/nbapp1-containerapp.yaml`
  - `manifests/nbrly/nbapp2-containerapp.yaml`
  - `manifests/bloom/bmapp1-containerapp.yaml`
  - `manifests/bloom/bmapp2-containerapp.yaml`

## Adding New Templates

1. Create template file in `manifests/templates/`
2. Use `#{PLACEHOLDER}#` syntax for dynamic values
3. Update `scripts/helpers/generate-manifests.sh`:
   - Add app configuration to the `apps` array
   - Map to the appropriate template
4. Test generation:
   ```bash
   ./scripts/helpers/generate-manifests.sh
   ```

## Template Best Practices

### Placeholder Format
- Always use `#{PLACEHOLDER}#` format
- Use uppercase with underscores for readability
- Choose descriptive names

### Configuration Organization
- **Global values**: config/parameters-dev.json
- **Tenant values**: config/{tenant}/parameters-dev.json
- **App values**: apps section in tenant config

### Version Control
- **Templates** (this directory): Committed to git
- **Generated manifests** (manifests/{tenant}/): May be git-ignored since they're generated
- **Configuration files**: Committed to git (without secrets)

## Integration with Azure Resources

Templates are designed to integrate with Azure resources created by `iac-cli`:

### User Assigned Managed Identities
- Created in: `iac-cli/scripts/{tenant}/02-create-uami.sh`
- Used for:
  - ACR authentication (AcrPull role)
  - Key Vault secret access
  - Azure service authentication

### Azure Key Vault
- Created in: `iac-cli/scripts/nbrly/03-create-keyvault.sh`
- Stores:
  - PostgreSQL connection strings
  - Other application secrets
- Access via: UAMI with Key Vault Secrets User role

### Azure Container Registry
- Created in: `iac-cli/scripts/01-create-acr.sh`
- Features:
  - No password authentication
  - UAMI-based pull access
  - Tenant-specific image organization

### PostgreSQL Flexible Servers
- Created in: `iac-cli/scripts/{tenant}/04-create-postgresql.sh`
- Connection strings stored in Key Vault
- Referenced in templates with `#{DB_SECRET_NAME}#`

## Troubleshooting

### Missing Placeholders
If generated manifests contain unreplaced placeholders:
1. Check configuration files have all required values
2. Verify placeholder names match exactly (case-sensitive)
3. Review `scripts/helpers/generate-manifests.sh` for mapping

### UAMI Client ID Issues
The `#{*_UAMI_CLIENT_ID}#` placeholders are replaced at deployment time:
1. `generate-manifests.sh` leaves them as placeholders
2. `deploy-yaml.sh` fetches actual client IDs from Azure
3. Client IDs are replaced just before deployment

### Template Validation
To validate a template before generation:
```bash
# Check for placeholder syntax
grep -o '#{[A-Z_]*}#' manifests/templates/your-template.yaml.template

# Verify against configuration
cat config/parameters-dev.json | jq -r 'keys[]'
```

## See Also

- [Manifest Generation Script](../../scripts/helpers/generate-manifests.sh)
- [Deployment Script](../../scripts/deploy-yaml.sh)
- [Configuration System](../config/README.md)
- [Azure Integration Guide](../docs/azure-resources-integration.md)
