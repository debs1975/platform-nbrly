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
    echo "Usage: ./03-deploy-tenant-resources.sh <tenant>"
    echo "Example: ./03-deploy-tenant-resources.sh nbrly"
    echo "         ./03-deploy-tenant-resources.sh bloom"
    exit 1
fi

# Validate tenant
if [[ ! "$TENANT" =~ ^(nbrly|bloom)$ ]]; then
    echo "ERROR: Invalid tenant: $TENANT (must be 'nbrly' or 'bloom')"
    exit 1
fi

# Configuration files
CONFIG_DIR="$PROJECT_ROOT/config"
PARAMETERS_FILE="$CONFIG_DIR/parameters-dev.json"
INFRA_FILE="$CONFIG_DIR/infra-dev.json"
TENANT_CONFIG="$CONFIG_DIR/${TENANT}/parameters-dev.json"

# Source helper functions
source "$SCRIPT_DIR/helpers/logging.sh"
source "$SCRIPT_DIR/helpers/config-parser.sh"
source "$SCRIPT_DIR/helpers/azure-login.sh"

# Setup logging
setup_logging "tenant-$TENANT" "dev"

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
LOCATION=$(parse_config "$PARAMETERS_FILE" ".location")
VNET_NAME=$(parse_config "$INFRA_FILE" ".networking.virtualNetwork.name")

# Tenant-specific configuration
TENANT_NAME=$(parse_config "$TENANT_CONFIG" ".tenantName")
TENANT_DISPLAY_NAME=$(parse_config "$TENANT_CONFIG" ".tenantDisplayName")
DOMAIN=$(parse_config "$TENANT_CONFIG" ".domain")

# Container App Environment configuration
CAE_NAME=$(parse_config "$TENANT_CONFIG" ".containerAppEnvironment.name")
CAE_SUBNET=$(parse_config "$TENANT_CONFIG" ".containerAppEnvironment.subnet")
CAE_DEFAULT_DOMAIN=$(parse_config "$TENANT_CONFIG" ".containerAppEnvironment.defaultDomain")

# Managed Identity configuration
UAMI_NAME=$(parse_config "$TENANT_CONFIG" ".managedIdentity.name")

# Private DNS Zone configuration
PRIVATE_DNS_ZONE=$(parse_config "$TENANT_CONFIG" ".privateDnsZone.name")
VNET_LINK_NAME=$(parse_config "$TENANT_CONFIG" ".privateDnsZone.vnetLinkName")

log_info "Configuration loaded successfully:"
log_info "  Tenant: $TENANT_DISPLAY_NAME ($TENANT_NAME)"
log_info "  Domain: $DOMAIN"
log_info "  Container App Environment: $CAE_NAME"
log_info "  Managed Identity: $UAMI_NAME"
log_info "  Private DNS Zone: $PRIVATE_DNS_ZONE"

if [ -f "$infra_file" ]; then
  backup_file="${backup_dir_config}/$(basename "$infra_file").backup-${timestamp}"
  cp "$infra_file" "$backup_file"
  log_info "Created backup: $backup_file"
# Login to Azure
azure_login

# Set Azure subscription
log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

# 1. Create User-Assigned Managed Identity
log_info "Creating User-Assigned Managed Identity: $UAMI_NAME"
if ! az identity show --name "$UAMI_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az identity create \
        --name "$UAMI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags Environment="dev" Project="astra" Tenant="$TENANT_NAME" \
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

# 2. Create Container App Environment
log_info "Creating Container App Environment: $CAE_NAME"
if ! az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az containerapp env create \
        --name "$CAE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --infrastructure-subnet-resource-id "$(parse_config "$INFRA_FILE" ".networking.subnets.${TENANT}CAE.id")" \
        --internal-only true \
        --tags Environment="dev" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created Container App Environment: $CAE_NAME"
else
    log_info "Container App Environment already exists: $CAE_NAME"
fi

# 3. Create Private DNS Zone for Container App Environment
log_info "Creating Private DNS Zone: $PRIVATE_DNS_ZONE"
if ! az network private-dns zone show --name "$PRIVATE_DNS_ZONE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network private-dns zone create \
        --name "$PRIVATE_DNS_ZONE" \
        --resource-group "$RESOURCE_GROUP" \
        --tags Environment="dev" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created Private DNS Zone: $PRIVATE_DNS_ZONE"
else
    log_info "Private DNS Zone already exists: $PRIVATE_DNS_ZONE"
fi

# 4. Create VNet Link for Private DNS Zone
log_info "Creating VNet Link for Private DNS Zone: $VNET_LINK_NAME"
if ! az network private-dns link vnet show --name "$VNET_LINK_NAME" --zone-name "$PRIVATE_DNS_ZONE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network private-dns link vnet create \
        --name "$VNET_LINK_NAME" \
        --zone-name "$PRIVATE_DNS_ZONE" \
        --resource-group "$RESOURCE_GROUP" \
        --virtual-network "$VNET_NAME" \
        --registration-enabled false \
        --tags Environment="dev" Project="astra" Tenant="$TENANT_NAME" \
        --output table
    log_success "Created VNet Link: $VNET_LINK_NAME"
else
    log_info "VNet Link already exists: $VNET_LINK_NAME"
fi

# 5. Assign AcrPull role to UAMI for Container Registry
ACR_ID=$(parse_config "$INFRA_FILE" ".containerRegistry.id")
log_info "Assigning AcrPull role to UAMI for Container Registry"
if ! az role assignment list --assignee "$UAMI_PRINCIPAL_ID" --role "AcrPull" --scope "$ACR_ID" --query "[0].id" -o tsv &>/dev/null; then
    az role assignment create \
        --assignee "$UAMI_PRINCIPAL_ID" \
        --role "AcrPull" \
        --scope "$ACR_ID"
    log_success "Assigned AcrPull role to UAMI"
else
    log_info "UAMI already has AcrPull role on Container Registry"
fi
    --query "[0].id" -o tsv 2>/dev/null || true)

if [ -z "$roleAssignment" ]; then
    log_info "Granting UAMI AcrPull role on ACR"
    az role assignment create \
        --assignee-object-id "$uamiPrincipalId" \
        --assignee-principal-type "ServicePrincipal" \
        --role "AcrPull" \
        --scope "$acrId"
    log_success "Assigned AcrPull role to UAMI"
else
    log_info "UAMI already has AcrPull role on ACR"
fi

# Assign Key Vault Secrets User role to UAMI for reading secrets
# 6. Assign Key Vault Secrets User role to UAMI
KV_ID=$(parse_config "$INFRA_FILE" ".keyVault.id")
log_info "Assigning Key Vault Secrets User role to UAMI"
if ! az role assignment list --assignee "$UAMI_PRINCIPAL_ID" --role "Key Vault Secrets User" --scope "$KV_ID" --query "[0].id" -o tsv &>/dev/null; then
    az role assignment create \
        --assignee "$UAMI_PRINCIPAL_ID" \
        --role "Key Vault Secrets User" \
        --scope "$KV_ID"
    log_success "Assigned Key Vault Secrets User role to UAMI"
else
    log_info "UAMI already has Key Vault Secrets User role"
fi

# 7. Update Configuration Files
log_info "Updating configuration files with deployed resources..."

# Get deployed resource details
UAMI_ID=$(az identity show --name "$UAMI_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
CAE_ID=$(az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
CAE_STATIC_IP=$(az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.staticIp" -o tsv)
CAE_DEFAULT_DOMAIN=$(az containerapp env show --name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.defaultDomain" -o tsv)

# Update tenant configuration file
update_config "$TENANT_CONFIG_FILE" ".managedIdentity.name" "$UAMI_NAME"
update_config "$TENANT_CONFIG_FILE" ".managedIdentity.id" "$UAMI_ID"
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
log_info "  • Managed Identity:         $UAMI_NAME"
log_info "  • Container App Environment: $CAE_NAME"
log_info "  • Static IP:                $CAE_STATIC_IP"  
log_info "  • Default Domain:           $CAE_DEFAULT_DOMAIN"
log_info "  • Private DNS Zone:         $PRIVATE_DNS_ZONE"
log_info ""
log_info "Next Steps:"
log_info "  1. Configure Application Gateway routing:"
log_info "     ./04-configure-routing.sh $TENANT_NAME dev"
log_info "  2. Deploy Container Apps from app-gtwy-apps folder"
log_info "========================================================================="
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file (ensure .resources.tenants exists)
jq --arg tenant "$tenantName" --arg caeName "$caeName" --arg caeId "$caeId" --arg caeStaticIp "$caeStaticIp" \
   '.resources.tenants //= {} | .resources.tenants[$tenant] += {containerAppEnv: {name: $caeName, id: $caeId, staticIp: $caeStaticIp}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

log_success "Container App Environment deployment complete for '${tenantName}'"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Next Steps:"
log_info "1. Configure Application Gateway routing (using CAE static IP):"
log_info "   ./04-configure-routing.sh ${TENANT} ${PROJECT} ${ENV}"
log_info "2. Deploy Container Apps from app-gtwy-apps folder"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
