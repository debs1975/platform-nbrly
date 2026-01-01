#!/bin/bash

# =============================================================================
# Tenant Resources Deployment Script
# Creates Container App Environment and related resources for a specific tenant
# =============================================================================

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Get tenant name parameter (required)
TENANT=${1:-""}
if [ -z "$TENANT" ]; then
    echo "ERROR: Tenant name is required"
    echo "Usage: ./03-deploy-tenant-resources.sh <tenant> [environment]"
    echo "Example: ./03-deploy-tenant-resources.sh nbrly dev"
    echo "         ./03-deploy-tenant-resources.sh bloom stage"
    exit 1
fi

# Get environment parameter (default to dev if not provided)
ENV=${2:-dev}

# Validate environment
if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
    echo "ERROR: Invalid environment: $ENV (must be 'dev', 'stage', or 'prod')"
    exit 1
fi

# Validate tenant
if [[ ! "$TENANT" =~ ^(nbrly|bloom)$ ]]; then
    echo "ERROR: Invalid tenant: $TENANT (must be 'nbrly' or 'bloom')"
    exit 1
fi

# Configuration files
CONFIG_DIR="$PROJECT_ROOT/config"
PARAMETERS_FILE="$CONFIG_DIR/parameters-${ENV}.json"
INFRA_FILE="$CONFIG_DIR/infra-${ENV}.json"
TENANT_CONFIG="$CONFIG_DIR/${TENANT}/parameters-${ENV}.json"

# Source helper functions
source "$SCRIPT_DIR/helpers/logging.sh"
source "$SCRIPT_DIR/helpers/config-parser.sh"
source "$SCRIPT_DIR/helpers/azure-login.sh"

# Setup logging
setup_logging "tenant-$TENANT" "$ENV"

# Trap errors
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

log_info "============================================================================"
log_info "Starting tenant resources deployment for: $TENANT"
log_info "============================================================================"

# Validate configuration files
if [ ! -f "$PARAMETERS_FILE" ]; then
    log_error "Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

if [ ! -f "$INFRA_FILE" ]; then
    log_error "Infrastructure file not found: $INFRA_FILE"
    exit 1
fi

if [ ! -f "$TENANT_CONFIG" ]; then
    log_error "Tenant configuration file not found: $TENANT_CONFIG"
    exit 1
fi

# Parse configuration
SUBSCRIPTION_ID=$(parse_config "$INFRA_FILE" ".subscription.id")
RESOURCE_GROUP=$(parse_config "$INFRA_FILE" ".resourceGroup.name")
LOCATION=$(parse_config "$PARAMETERS_FILE" ".resourceGroup.location")
VNET_NAME=$(parse_config "$INFRA_FILE" ".networking.virtualNetwork.name")
ACR_NAME=$(parse_config "$INFRA_FILE" ".containerRegistry.name")
TENANT_CONFIG_FILE="$TENANT_CONFIG"

# Derive project and region from parameters for naming
PROJECT=$(parse_config "$PARAMETERS_FILE" ".project")
REGION=$(parse_config "$PARAMETERS_FILE" ".region")

# Derive Log Analytics Workspace name following naming standards
LAW_NAME="${PROJECT}-${ENV}-${REGION}-law"

# Tenant-specific configuration
TENANT_NAME=$(parse_config "$TENANT_CONFIG" ".tenantName")
TENANT_DISPLAY_NAME=$(parse_config "$TENANT_CONFIG" ".tenantDisplayName")
DOMAIN=$(parse_config "$TENANT_CONFIG" ".domain")

# Container App Environment configuration
CAE_NAME=$(parse_config "$TENANT_CONFIG" ".containerAppEnvironment.name")
CAE_SUBNET=$(parse_config "$TENANT_CONFIG" ".containerAppEnvironment.subnet")
CAE_DEFAULT_DOMAIN=$(parse_config "$TENANT_CONFIG" ".containerAppEnvironment.defaultDomain" 2>/dev/null || echo "")

# Managed Identity configuration
UAMI_NAME=$(parse_config "$TENANT_CONFIG" ".managedIdentity.name")

# KeyVault configuration (tenant-specific)
KV_NAME=$(parse_config "$TENANT_CONFIG" ".keyVault.name")

# Storage Account configuration (tenant-specific)
SA_NAME=$(parse_config "$TENANT_CONFIG" ".storageAccount.name")

# Private DNS Zone configuration will be set after CAE creation
# It is derived from the CAE's defaultDomain
PRIVATE_DNS_ZONE=""
VNET_LINK_NAME=$(parse_config "$TENANT_CONFIG" ".privateDnsZone.vnetLinkName")

log_info "Configuration loaded successfully:"
log_info "  Tenant: $TENANT_DISPLAY_NAME ($TENANT_NAME)"
log_info "  Domain: $DOMAIN"
log_info "  Container App Environment: $CAE_NAME"
log_info "  Managed Identity: $UAMI_NAME"
log_info "  Private DNS Zone: $PRIVATE_DNS_ZONE"

# Login to Azure with environment-specific credentials
azure_login "$ENV"

# Set Azure subscription
if [ -n "$SUBSCRIPTION_ID" ] && [ "$SUBSCRIPTION_ID" != "null" ]; then
    log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
else
    log_warning "No subscription ID found in infra file. Using current subscription context."
    CURRENT_SUBSCRIPTION=$(az account show --query "id" -o tsv 2>/dev/null || echo "")
    if [ -n "$CURRENT_SUBSCRIPTION" ]; then
        log_info "Current subscription: $CURRENT_SUBSCRIPTION"
        SUBSCRIPTION_ID="$CURRENT_SUBSCRIPTION"
    else
        log_error "No subscription context available. Please ensure you're logged in and have a valid subscription."
        exit 1
    fi
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 1: Creating User-Assigned Managed Identity                              │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Managed Identity Configuration:"
log_info "    • Name:         $UAMI_NAME"
log_info "    • Location:     $LOCATION"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • Tenant:       $TENANT_NAME"
log_info ""

# 1. Create User-Assigned Managed Identity
log_info "Creating User-Assigned Managed Identity: $UAMI_NAME"
if ! az identity show --name "$UAMI_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az identity create \
        --name "$UAMI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags Environment="$ENV" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created Managed Identity: $UAMI_NAME"
    # Wait for Azure AD replication
    log_info "Waiting 30 seconds for Managed Identity replication..."
    sleep 30
else
    log_info "Managed Identity already exists: $UAMI_NAME"
fi

# Get UAMI Principal ID for role assignments
UAMI_PRINCIPAL_ID=$(az identity show --name "$UAMI_NAME" --resource-group "$RESOURCE_GROUP" --query "principalId" -o tsv)

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 2: Creating Tenant-Specific Key Vault                                  │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Key Vault Configuration:"
log_info "    • Name:         $KV_NAME"
log_info "    • Location:     $LOCATION"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • Tenant:       $TENANT_NAME"
log_info ""

# 2. Create Tenant-Specific Key Vault
log_info "Creating Key Vault: $KV_NAME"
if ! az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az keyvault create \
        --name "$KV_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --enable-rbac-authorization true \
        --tags Environment="$ENV" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created Key Vault: $KV_NAME"
else
    log_info "Key Vault already exists: $KV_NAME"
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 2.5: Creating Tenant-Specific Storage Account                          │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Storage Account Configuration:"
log_info "    • Name:         $SA_NAME"
log_info "    • Location:     $LOCATION"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • Tenant:       $TENANT_NAME"
log_info "    • SKU:          Standard_LRS"
log_info ""

# 2.5. Create Tenant-Specific Storage Account
log_info "Creating Storage Account: $SA_NAME"
if ! az storage account show --name "$SA_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az storage account create \
        --name "$SA_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        --tags Environment="$ENV" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created Storage Account: $SA_NAME"
else
    log_info "Storage Account already exists: $SA_NAME"
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 3: Creating Log Analytics Workspace                                     │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Log Analytics Workspace Configuration:"
log_info "    • Name:         $LAW_NAME"
log_info "    • Location:     $LOCATION"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • SKU:          PerGB2018"
log_info ""

# 3. Create Log Analytics Workspace for Container App Environment monitoring
log_info "Creating Log Analytics Workspace: $LAW_NAME"
if ! az monitor log-analytics workspace show --workspace-name "$LAW_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az monitor log-analytics workspace create \
        --workspace-name "$LAW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags Environment="$ENV" Project="astra" \
        --output table
    log_success "Created Log Analytics Workspace: $LAW_NAME"
else
    log_info "Log Analytics Workspace already exists: $LAW_NAME"
fi

# Get Log Analytics Workspace ID and Key for Container App Environment
LAW_ID=$(az monitor log-analytics workspace show --workspace-name "$LAW_NAME" --resource-group "$RESOURCE_GROUP" --query "customerId" -o tsv)
LAW_KEY=$(az monitor log-analytics workspace get-shared-keys --workspace-name "$LAW_NAME" --resource-group "$RESOURCE_GROUP" --query "primarySharedKey" -o tsv)

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 4: Creating Container App Environment                                   │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Container App Environment Configuration:"
log_info "    • Name:         $CAE_NAME"
log_info "    • Location:     $LOCATION"
log_info "    • Subnet:       $CAE_SUBNET"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • Tenant:       $TENANT_NAME"
log_info "    • Log Analytics: $LAW_NAME"
log_info ""

# 4. Create Container App Environment
log_info "Creating Container App Environment: $CAE_NAME"
if ! az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    # Get the subnet resource ID dynamically
    SUBNET_ID=$(az network vnet subnet show --name "$CAE_SUBNET" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
    
    az containerapp env create \
        --name "$CAE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --infrastructure-subnet-resource-id "$SUBNET_ID" \
        --logs-workspace-id "$LAW_ID" \
        --logs-workspace-key "$LAW_KEY" \
        --internal-only true \
        --tags Environment="$ENV" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created Container App Environment: $CAE_NAME"
else
    log_info "Container App Environment already exists: $CAE_NAME"
fi

# Retrieve CAE's default domain and use it as Private DNS Zone name
log_info "Retrieving Container App Environment details..."
CAE_DEFAULT_DOMAIN=$(az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.defaultDomain" -o tsv)
PRIVATE_DNS_ZONE="$CAE_DEFAULT_DOMAIN"
log_info "Derived Private DNS Zone name from CAE: $PRIVATE_DNS_ZONE"

# Store DNS zone name in infra file for future reference
log_info "Storing Private DNS Zone name in infrastructure file..."
jq --arg tenant "$TENANT" --arg dnsZone "$PRIVATE_DNS_ZONE" \
   '.networking.privateDnsZones[$tenant] //= {} | .networking.privateDnsZones[$tenant].name = $dnsZone' \
   "$INFRA_FILE" > "${INFRA_FILE}.tmp" && mv "${INFRA_FILE}.tmp" "$INFRA_FILE"

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 5: Creating Private DNS Zone                                            │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Private DNS Zone Configuration:"
log_info "    • Name:         $PRIVATE_DNS_ZONE"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • Tenant:       $TENANT_NAME"
log_info ""

# 5. Create Private DNS Zone for Container App Environment
log_info "Creating Private DNS Zone: $PRIVATE_DNS_ZONE"
if ! az network private-dns zone show --name "$PRIVATE_DNS_ZONE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network private-dns zone create \
        --name "$PRIVATE_DNS_ZONE" \
        --resource-group "$RESOURCE_GROUP" \
        --tags Environment="$ENV" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created Private DNS Zone: $PRIVATE_DNS_ZONE"
else
    log_info "Private DNS Zone already exists: $PRIVATE_DNS_ZONE"
fi

# Get Container App Environment static IP for A record creation
CAE_STATIC_IP=$(az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.staticIp" -o tsv)

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 5.5: Creating A Record Set in Private DNS Zone                         │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  A Record Configuration:"
log_info "    • Record Name:   *"
log_info "    • DNS Zone:      $PRIVATE_DNS_ZONE"
log_info "    • Target IP:     $CAE_STATIC_IP"
log_info "    • Resource Grp:  $RESOURCE_GROUP"
log_info ""

# Create wildcard A record pointing to Container App Environment static IP
log_info "Creating wildcard A record (*) pointing to CAE static IP: $CAE_STATIC_IP"
if ! az network private-dns record-set a show --name "*" --zone-name "$PRIVATE_DNS_ZONE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network private-dns record-set a create \
        --name "*" \
        --zone-name "$PRIVATE_DNS_ZONE" \
        --resource-group "$RESOURCE_GROUP" \
        --output table
    
    az network private-dns record-set a add-record \
        --record-set-name "*" \
        --zone-name "$PRIVATE_DNS_ZONE" \
        --resource-group "$RESOURCE_GROUP" \
        --ipv4-address "$CAE_STATIC_IP"
    
    log_success "Created wildcard A record pointing to $CAE_STATIC_IP"
else
    log_info "Wildcard A record already exists in Private DNS Zone"
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 6: Creating VNet Link for Private DNS Zone                             │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  VNet Link Configuration:"
log_info "    • Link Name:     $VNET_LINK_NAME"
log_info "    • DNS Zone:      $PRIVATE_DNS_ZONE"
log_info "    • Virtual Net:   $VNET_NAME"
log_info "    • Resource Grp:  $RESOURCE_GROUP"
log_info ""

# 6. Create VNet Link for Private DNS Zone
log_info "Creating VNet Link for Private DNS Zone: $VNET_LINK_NAME"
if ! az network private-dns link vnet show --name "$VNET_LINK_NAME" --zone-name "$PRIVATE_DNS_ZONE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network private-dns link vnet create \
        --name "$VNET_LINK_NAME" \
        --zone-name "$PRIVATE_DNS_ZONE" \
        --resource-group "$RESOURCE_GROUP" \
        --virtual-network "$VNET_NAME" \
        --registration-enabled false \
        --tags Environment="$ENV" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created VNet Link: $VNET_LINK_NAME"
else
    log_info "VNet Link already exists: $VNET_LINK_NAME"
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 7: Assigning AcrPull Role to Managed Identity                          │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  AcrPull Role Assignment:"
log_info "    • Managed Identity: $UAMI_NAME"
log_info "    • Role:             AcrPull"
log_info "    • Container Reg:    $ACR_NAME"
log_info ""

# 7. Assign AcrPull role to UAMI for Container Registry
# Get ACR ID dynamically if not in config
ACR_ID=$(parse_config "$INFRA_FILE" ".containerRegistry.id" 2>/dev/null || echo "")
if [ -z "$ACR_ID" ]; then
    log_info "ACR ID not found in config, retrieving from Azure..."
    ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
fi

log_info "Assigning AcrPull role to UAMI for Container Registry"
ACRPULL_ROLE_EXISTS=$(az role assignment list --assignee "$UAMI_PRINCIPAL_ID" --role "AcrPull" --scope "$ACR_ID" -o json | jq -r 'length')
if [ "$ACRPULL_ROLE_EXISTS" -eq 0 ]; then
    az role assignment create \
        --assignee "$UAMI_PRINCIPAL_ID" \
        --role "AcrPull" \
        --scope "$ACR_ID"
    log_success "Assigned AcrPull role to UAMI"
else
    log_info "UAMI already has AcrPull role on Container Registry"
fi

# Assign Key Vault Secrets User role to UAMI for reading secrets
log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 8: Assigning Key Vault Secrets User Role                               │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Key Vault RBAC Configuration:"
log_info "    • Managed Identity: $UAMI_NAME"
log_info "    • Role:             Key Vault Secrets User"
log_info "    • Key Vault:        $KV_NAME"
log_info ""

# 8. Assign Key Vault Secrets User role to UAMI
# Get Key Vault ID dynamically if not in config
KV_ID=$(parse_config "$INFRA_FILE" ".keyVaults.${TENANT}.id" 2>/dev/null || echo "")
if [ -z "$KV_ID" ]; then
    log_info "Key Vault ID not found in config, retrieving from Azure..."
    KV_ID=$(az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
fi

log_info "Assigning Key Vault Secrets User role to UAMI"
KV_SECRETS_ROLE_EXISTS=$(az role assignment list --assignee "$UAMI_PRINCIPAL_ID" --role "Key Vault Secrets User" --scope "$KV_ID" -o json | jq -r 'length')
if [ "$KV_SECRETS_ROLE_EXISTS" -eq 0 ]; then
    az role assignment create \
        --assignee "$UAMI_PRINCIPAL_ID" \
        --role "Key Vault Secrets User" \
        --scope "$KV_ID"
    log_success "Assigned Key Vault Secrets User role to UAMI"
else
    log_info "Managed Identity already has Key Vault Secrets User role"
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 8.5: Assigning Storage Account RBAC Roles                              │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Storage Account RBAC Configuration:"
log_info "    • Managed Identity: $UAMI_NAME"
log_info "    • Storage Account:  $SA_NAME"
log_info "    • Roles:"
log_info "      - Storage Blob Data Contributor (Read/Write/Delete blobs)"
log_info "      - Storage Queue Data Contributor (Read/Write/Delete queues)"
log_info ""

# 8.5. Assign Storage roles to UAMI
# Get Storage Account ID dynamically if not in config
SA_ID=$(parse_config "$INFRA_FILE" ".storageAccounts.${TENANT}.id" 2>/dev/null || echo "")
if [ -z "$SA_ID" ]; then
    log_info "Storage Account ID not found in config, retrieving from Azure..."
    SA_ID=$(az storage account show --name "$SA_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
fi

# Assign Storage Blob Data Contributor role (Read/Write/Delete access to blob containers and data)
log_info "Assigning Storage Blob Data Contributor role to UAMI..."
BLOB_ROLE_EXISTS=$(az role assignment list --assignee "$UAMI_PRINCIPAL_ID" --role "Storage Blob Data Contributor" --scope "$SA_ID" -o json | jq -r 'length')
if [ "$BLOB_ROLE_EXISTS" -eq 0 ]; then
    az role assignment create \
        --assignee "$UAMI_PRINCIPAL_ID" \
        --role "Storage Blob Data Contributor" \
        --scope "$SA_ID"
    log_success "Assigned Storage Blob Data Contributor role to UAMI"
else
    log_info "Managed Identity already has Storage Blob Data Contributor role"
fi

# Assign Storage Queue Data Contributor role (for queue operations if needed)
log_info "Assigning Storage Queue Data Contributor role to UAMI..."
QUEUE_ROLE_EXISTS=$(az role assignment list --assignee "$UAMI_PRINCIPAL_ID" --role "Storage Queue Data Contributor" --scope "$SA_ID" -o json | jq -r 'length')
if [ "$QUEUE_ROLE_EXISTS" -eq 0 ]; then
    az role assignment create \
        --assignee "$UAMI_PRINCIPAL_ID" \
        --role "Storage Queue Data Contributor" \
        --scope "$SA_ID"
    log_success "Assigned Storage Queue Data Contributor role to UAMI"
else
    log_info "Managed Identity already has Storage Queue Data Contributor role"
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 9: Updating Configuration Files                                        │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Configuration Update Details:"
log_info "    • Managed Identity: $UAMI_NAME -> Config file"
log_info "    • Container App:   $CAE_NAME -> Config file"
log_info "    • DNS Zone:        $PRIVATE_DNS_ZONE -> Config file"
log_info ""

# 9. Update Configuration Files
log_info "Updating configuration files with deployed resources..."

# Get deployed resource details
UAMI_ID=$(az identity show --name "$UAMI_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
KV_ID=$(az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
SA_ID=$(az storage account show --name "$SA_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
CAE_ID=$(az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
CAE_STATIC_IP=$(az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.staticIp" -o tsv)
CAE_DEFAULT_DOMAIN=$(az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.defaultDomain" -o tsv)

# Update tenant configuration file
update_config "$TENANT_CONFIG_FILE" ".managedIdentity.name" "$UAMI_NAME"
update_config "$TENANT_CONFIG_FILE" ".managedIdentity.id" "$UAMI_ID"
update_config "$TENANT_CONFIG_FILE" ".keyVault.name" "$KV_NAME"
update_config "$TENANT_CONFIG_FILE" ".keyVault.id" "$KV_ID"
update_config "$TENANT_CONFIG_FILE" ".storageAccount.name" "$SA_NAME"
update_config "$TENANT_CONFIG_FILE" ".storageAccount.id" "$SA_ID"
update_config "$TENANT_CONFIG_FILE" ".containerAppEnvironment.name" "$CAE_NAME"
update_config "$TENANT_CONFIG_FILE" ".containerAppEnvironment.id" "$CAE_ID"
update_config "$TENANT_CONFIG_FILE" ".containerAppEnvironment.staticIp" "$CAE_STATIC_IP"
update_config "$TENANT_CONFIG_FILE" ".containerAppEnvironment.defaultDomain" "$CAE_DEFAULT_DOMAIN"
update_config "$TENANT_CONFIG_FILE" ".privateDns.zoneName" "$PRIVATE_DNS_ZONE"
update_config "$TENANT_CONFIG_FILE" ".privateDns.vnetLinkName" "$VNET_LINK_NAME"

log_success "========================================================================="
log_success "Tenant Resources Deployment Complete for '$TENANT_NAME'"
log_success "========================================================================="
log_info "Deployed Resources:"
log_info "  • Managed Identity:          $UAMI_NAME"
log_info "  • Key Vault:                 $KV_NAME"
log_info "  • Storage Account:           $SA_NAME"
log_info "  • Container App Environment: $CAE_NAME"
log_info "  • Static IP:                 $CAE_STATIC_IP"  
log_info "  • Default Domain:            $CAE_DEFAULT_DOMAIN"
log_info "  • Private DNS Zone:          $PRIVATE_DNS_ZONE"
log_info ""
log_info "Next Steps:"
log_info "  1. Configure Application Gateway routing:"
log_info "     ./04-configure-routing.sh $TENANT_NAME $ENV"
log_info "  2. Deploy Container Apps from app-gtwy-apps folder"
log_info "==========================================================================="
