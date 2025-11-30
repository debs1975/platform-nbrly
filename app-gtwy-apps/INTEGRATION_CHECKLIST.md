# Integration Checklist: iac-cli → app-gtwy-apps

This checklist ensures all Azure infrastructure resources created by `iac-cli` are properly integrated into `app-gtwy-apps`.

## ✅ Completed Integration Tasks

### Configuration Files

- [x] **Global Configuration** (`config/parameters-dev.json`)
  - [x] Added `keyVault` section with `astradeveastuskv`
  - [x] Added Key Vault secret references for database connections
  - [x] Updated `logAnalyticsWorkspace` to `astra-dev-eastus-law`

- [x] **NBRLY Tenant Configuration** (`config/nbrly/parameters-dev.json`)
  - [x] Added `managedIdentity` section with `nbrly-dev-uami`
  - [x] Added `database` section with Key Vault reference
  - [x] Updated application environment variables with `AZURE_CLIENT_ID`
  - [x] Added `secrets` array for Key Vault secret injection

- [x] **BLOOM Tenant Configuration** (`config/bloom/parameters-dev.json`)
  - [x] Added `managedIdentity` section with `bloom-dev-uami`
  - [x] Added `database` section with Key Vault reference
  - [x] Updated application environment variables with `AZURE_CLIENT_ID`
  - [x] Added `secrets` array for Key Vault secret injection

### Deployment Scripts

- [x] **NBRLY Deployment** (`scripts/deploy-nbrly.sh`)
  - [x] Read UAMI configuration from tenant config
  - [x] Added `--registry-identity` for ACR authentication
  - [x] Added `--user-assigned` to assign UAMI to Container Apps
  - [x] Added Key Vault secret configuration for nbapp2
  - [x] Added automatic `DATABASE_URL` environment variable

- [x] **BLOOM Deployment** (`scripts/deploy-bloom.sh`)
  - [x] Read UAMI configuration from tenant config
  - [x] Added `--registry-identity` for ACR authentication
  - [x] Added `--user-assigned` to assign UAMI to Container Apps
  - [x] Added Key Vault secret configuration for bmapp2
  - [x] Added automatic `DATABASE_URL` environment variable

### Helper Scripts

- [x] **UAMI ID Population** (`scripts/helpers/populate-uami-ids.sh`)
  - [x] Queries Azure for actual UAMI client IDs and principal IDs
  - [x] Updates tenant configuration files
  - [x] Validates JSON after updates
  - [x] Made executable with proper permissions

### Documentation

- [x] **Azure Resources Integration Guide** (`docs/azure-resources-integration.md`)
  - [x] Overview of integrated resources
  - [x] Managed identity implementation details
  - [x] Key Vault integration pattern
  - [x] Security considerations
  - [x] Troubleshooting guide
  - [x] Code examples

- [x] **Updated README** (`README.md`)
  - [x] Added iac-cli prerequisite section
  - [x] Added UAMI ID population step
  - [x] Enhanced Configuration section
  - [x] Added managed identity security section
  - [x] Added documentation links

- [x] **Integration Summary** (`AZURE_INTEGRATION_SUMMARY.md`)
  - [x] What was done
  - [x] Integration pattern diagram
  - [x] Deployment workflow
  - [x] Verification steps
  - [x] Next steps

## 📋 Pre-Deployment Checklist

Before deploying applications, verify the following:

### Infrastructure (iac-cli)

- [ ] All infrastructure deployed via `iac-cli/scripts/deploy-all.sh`
- [ ] User Managed Identities created:
  - [ ] `nbrly-dev-uami` exists
  - [ ] `bloom-dev-uami` exists
- [ ] UAMIs have AcrPull role on ACR
- [ ] Key Vault `astradeveastuskv` exists
- [ ] Key Vault has access policies for UAMIs
- [ ] Database secrets stored in Key Vault:
  - [ ] `nbrly-psql-connection-string`
  - [ ] `bloom-psql-connection-string`
- [ ] PostgreSQL servers created:
  - [ ] `nbrly-dev-psql`
  - [ ] `bloom-dev-psql`
- [ ] Azure Container Registry `astradevacr` exists
- [ ] Log Analytics Workspace `astra-dev-eastus-law` exists

### Configuration (app-gtwy-apps)

- [ ] Configuration files copied from iac-cli
- [ ] UAMI IDs populated using `populate-uami-ids.sh`
- [ ] All configuration files validated with `jq`
- [ ] Configuration files in git (placeholders, not actual IDs)

### Deployment Scripts

- [ ] All deployment scripts updated to use managed identity
- [ ] Scripts executable (`chmod +x`)
- [ ] Helper scripts tested and working

## 🚀 Deployment Workflow

### One-Time Setup

```bash
# 1. Deploy infrastructure (iac-cli)
cd iac-cli/scripts
./00-deploy-all.sh

# 2. Verify infrastructure resources
az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg
az identity show --name bloom-dev-uami --resource-group astra-dev-eastus-rg
az keyvault show --name astradeveastuskv

# 3. Populate UAMI IDs in app-gtwy-apps
cd ../../app-gtwy-apps/scripts/helpers
./populate-uami-ids.sh

# 4. Verify configuration updates
cd ../..
jq '.managedIdentity' config/nbrly/parameters-dev.json
jq '.managedIdentity' config/bloom/parameters-dev.json
```

### Regular Deployment

```bash
cd app-gtwy-apps/scripts

# 1. Build and push images
./build-push-all.sh latest

# 2. Deploy container apps
./04-deploy-all.sh latest

# 3. Configure Application Gateway routing
./08-configure-routing.sh

# 4. Verify deployment
az containerapp show --name ca-nbrly-nbapp1-dev --resource-group astra-dev-eastus-rg
az containerapp show --name ca-bloom-bmapp1-dev --resource-group astra-dev-eastus-rg
```

## ✅ Verification Steps

### 1. Verify UAMI Configuration

```bash
# Check NBRLY UAMI
az identity show \
    --name nbrly-dev-uami \
    --resource-group astra-dev-eastus-rg \
    --query '{name:name, clientId:clientId, principalId:principalId}'

# Check BLOOM UAMI
az identity show \
    --name bloom-dev-uami \
    --resource-group astra-dev-eastus-rg \
    --query '{name:name, clientId:clientId, principalId:principalId}'

# Check AcrPull role assignment (NBRLY)
az role assignment list \
    --assignee $(az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg --query principalId -o tsv) \
    --scope $(az acr show --name astradevacr --query id -o tsv)
```

### 2. Verify Key Vault Integration

```bash
# Check Key Vault exists
az keyvault show --name astradeveastuskv

# Check access policies (NBRLY)
az keyvault show \
    --name astradeveastuskv \
    --query "properties.accessPolicies[?objectId=='$(az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg --query principalId -o tsv)']"

# Check secrets exist
az keyvault secret show --vault-name astradeveastuskv --name nbrly-psql-connection-string
az keyvault secret show --vault-name astradeveastuskv --name bloom-psql-connection-string
```

### 3. Verify Container App Deployment

```bash
# Check Container App identity (NBRLY)
az containerapp show \
    --name ca-nbrly-nbapp1-dev \
    --resource-group astra-dev-eastus-rg \
    --query "identity"

# Check Container App registry configuration
az containerapp show \
    --name ca-nbrly-nbapp1-dev \
    --resource-group astra-dev-eastus-rg \
    --query "properties.configuration.registries"

# Check secrets configuration (for nbapp2)
az containerapp secret list \
    --name ca-nbrly-nbapp2-dev \
    --resource-group astra-dev-eastus-rg
```

### 4. Test Application Endpoints

```bash
# Get Container App FQDN
NBRLY_FQDN=$(az containerapp show --name ca-nbrly-nbapp1-dev --resource-group astra-dev-eastus-rg --query "properties.configuration.ingress.fqdn" -o tsv)
BLOOM_FQDN=$(az containerapp show --name ca-bloom-bmapp1-dev --resource-group astra-dev-eastus-rg --query "properties.configuration.ingress.fqdn" -o tsv)

# Test health endpoints
curl https://$NBRLY_FQDN/health
curl https://$BLOOM_FQDN/health

# Test API endpoints
curl https://$NBRLY_FQDN/api/info
curl https://$BLOOM_FQDN/api/info
```

## 🔍 Troubleshooting

### Issue: UAMI Not Found

**Error**: `Managed identity 'nbrly-dev-uami' not found`

**Solution**:
```bash
# Verify UAMI exists
az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg

# If not found, redeploy infrastructure
cd iac-cli/scripts
./00-deploy-all.sh
```

### Issue: ACR Pull Failed

**Error**: `Failed to pull image from ACR`

**Solution**:
```bash
# Check AcrPull role assignment
az role assignment list \
    --assignee $(az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg --query principalId -o tsv) \
    --scope $(az acr show --name astradevacr --query id -o tsv)

# Re-assign role if missing
az role assignment create \
    --assignee $(az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg --query principalId -o tsv) \
    --role AcrPull \
    --scope $(az acr show --name astradevacr --query id -o tsv)
```

### Issue: Key Vault Access Denied

**Error**: `Access denied to Key Vault secret`

**Solution**:
```bash
# Check access policy
az keyvault show \
    --name astradeveastuskv \
    --query "properties.accessPolicies[?objectId=='$(az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg --query principalId -o tsv)']"

# Set access policy if missing
az keyvault set-policy \
    --name astradeveastuskv \
    --object-id $(az identity show --name nbrly-dev-uami --resource-group astra-dev-eastus-rg --query principalId -o tsv) \
    --secret-permissions get
```

### Issue: AZURE_CLIENT_ID Not Set

**Error**: `Environment variable AZURE_CLIENT_ID not found`

**Solution**:
```bash
# Run populate script
cd app-gtwy-apps/scripts/helpers
./populate-uami-ids.sh

# Verify configuration
jq '.managedIdentity.clientId' ../../config/nbrly/parameters-dev.json

# Redeploy container app
cd ..
./deploy-nbrly.sh latest
```

## 📊 Integration Validation

### Configuration Files

- ✅ `config/parameters-dev.json` has `keyVault` section
- ✅ `config/nbrly/parameters-dev.json` has `managedIdentity` section
- ✅ `config/bloom/parameters-dev.json` has `managedIdentity` section
- ✅ All configuration files are valid JSON

### Scripts

- ✅ `scripts/deploy-nbrly.sh` uses managed identity
- ✅ `scripts/deploy-bloom.sh` uses managed identity
- ✅ `scripts/helpers/populate-uami-ids.sh` is executable
- ✅ All scripts have proper error handling

### Documentation

- ✅ `docs/azure-resources-integration.md` created
- ✅ `AZURE_INTEGRATION_SUMMARY.md` created
- ✅ `README.md` updated with integration details
- ✅ All documentation accurate and complete

## 🎯 Success Criteria

- [x] All configuration files updated with Azure resource references
- [x] All deployment scripts use managed identity for ACR and Key Vault
- [x] Helper script created to populate UAMI IDs from Azure
- [x] Comprehensive documentation created
- [x] No hardcoded credentials in any file
- [x] All JSON configuration files valid
- [x] Integration pattern follows Azure best practices
- [x] Principle of least privilege applied to UAMIs
- [x] Tenant isolation maintained

## 📚 Reference Documents

- [Azure Resources Integration Guide](docs/azure-resources-integration.md)
- [Azure Integration Summary](AZURE_INTEGRATION_SUMMARY.md)
- [Configuration System Documentation](docs/configuration-system.md)
- [README](README.md)

---

**Status**: ✅ **COMPLETE**  
**Last Updated**: December 2024  
**Integration**: iac-cli → app-gtwy-apps  
**Security**: Managed Identity + Key Vault
