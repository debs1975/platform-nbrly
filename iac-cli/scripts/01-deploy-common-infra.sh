#!/bin/bash

# =============================================================================
# Common Infrastructure Deployment Script
# This script deploys the shared infrastructure components for the Astra platform
# =============================================================================

set -euo pipefail

# Script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration files
CONFIG_DIR="$PROJECT_ROOT/config"
PARAMETERS_FILE="$CONFIG_DIR/parameters-dev.json"
INFRA_FILE="$CONFIG_DIR/infra-dev.json"

# Source helper functions
source "$SCRIPT_DIR/helpers/logging.sh"
source "$SCRIPT_DIR/helpers/config-parser.sh"
source "$SCRIPT_DIR/helpers/azure-login.sh"

# Setup logging
setup_logging "common-infra" "dev"

# Trap errors
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

log_info "Starting common infrastructure deployment"
log_info "Using parameters: $PARAMETERS_FILE"
log_info "Using infrastructure: $INFRA_FILE"

# Validate configuration files exist
if [ ! -f "$PARAMETERS_FILE" ]; then
    log_error "Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

if [ ! -f "$INFRA_FILE" ]; then
    log_error "Infrastructure file not found: $INFRA_FILE"
    exit 1
fi

# Parse configuration from our reverse-engineered files
ENVIRONMENT=$(parse_config "$PARAMETERS_FILE" ".environment")
LOCATION=$(parse_config "$PARAMETERS_FILE" ".location")
SUBSCRIPTION_ID=$(parse_config "$INFRA_FILE" ".subscription.id")
RESOURCE_GROUP=$(parse_config "$INFRA_FILE" ".resourceGroup.name")

# Virtual Network configuration
VNET_NAME=$(parse_config "$INFRA_FILE" ".networking.virtualNetwork.name")
VNET_ADDRESS_PREFIX=$(parse_config "$INFRA_FILE" ".networking.virtualNetwork.addressPrefixes[0]")

# Subnet configurations
APPGTWY_SUBNET_NAME=$(parse_config "$INFRA_FILE" ".networking.subnets.appGateway.name")
APPGTWY_SUBNET_PREFIX=$(parse_config "$INFRA_FILE" ".networking.subnets.appGateway.addressPrefix")

NBRLY_SUBNET_NAME=$(parse_config "$INFRA_FILE" ".networking.subnets.nbrlyCAE.name")
NBRLY_SUBNET_PREFIX=$(parse_config "$INFRA_FILE" ".networking.subnets.nbrlyCAE.addressPrefix")

BLOOM_SUBNET_NAME=$(parse_config "$INFRA_FILE" ".networking.subnets.bloomCAE.name")
BLOOM_SUBNET_PREFIX=$(parse_config "$INFRA_FILE" ".networking.subnets.bloomCAE.addressPrefix")

# Private Endpoint Subnet configuration
PE_SUBNET_NAME=$(parse_config "$INFRA_FILE" ".networking.subnets.privateEndpoint.name")
PE_SUBNET_PREFIX=$(parse_config "$INFRA_FILE" ".networking.subnets.privateEndpoint.addressPrefix")



# Application Gateway configuration
AGW_NAME=$(parse_config "$INFRA_FILE" ".applicationGateway.name")
AGW_PIP_NAME=$(parse_config "$INFRA_FILE" ".applicationGateway.publicIPAddress.name")

# Key Vault configuration
KV_NAME=$(parse_config "$INFRA_FILE" ".keyVault.name")

# Container Registry configuration
ACR_NAME=$(parse_config "$INFRA_FILE" ".containerRegistry.name")

# Define the output file for generated infrastructure details
output_file="${SCRIPT_DIR}/../config/.generated/generated-infra-${ENV}.json"
infra_file="${SCRIPT_DIR}/../config/infra-${ENV}.json"

# Create backup directories if they don't exist
mkdir -p "${SCRIPT_DIR}/../config/.generated/.bak"
mkdir -p "${SCRIPT_DIR}/../config/.bak"

# Backup existing files if they exist
if [ -f "$output_file" ]; then
    backup_file="${SCRIPT_DIR}/../config/.generated/.bak/generated-infra-${ENV}.json.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backing up existing generated infrastructure file to: $backup_file"
    cp "$output_file" "$backup_file"
fi

if [ -f "$infra_file" ]; then
    backup_infra_file="${SCRIPT_DIR}/../config/.bak/infra-${ENV}.json.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backing up existing infrastructure tracking file to: $backup_infra_file"
    cp "$infra_file" "$backup_infra_file"
fi

# Initialize the output files
log_info "Initializing generated infrastructure file: $output_file"
echo '{}' | jq '.common = {} | .tenants = {}' > "$output_file"
log_info "Initializing infrastructure tracking file: $infra_file"
echo '{}' | jq '.project = $project | .environment = $env | .resources = {}' \
  --arg project "$project" --arg env "$ENV" > "$infra_file"

# Derive all resource names from project and environment
rgName="${project}-${ENV}-${region}-rg"
vnetName="${project}-${ENV}-${region}-vnet"
agwName="${project}-${ENV}-${region}-agw"
pipName="${project}-${ENV}-${region}-pip"
kvName="${project}${ENV}${region}kv" # Key Vault names have restrictions
acrName="${project}${ENV}${region}acr" # ACR names have restrictions
lawName="${project}-${ENV}-${region}-law"
agwUamiName="agw-managed-identity" # Managed identity for the AGW

# Print all inferred variables before deployment
log_info "======================================================"
log_info "Infrastructure Configuration:"
log_info "======================================================"
log_info "Environment:          $ENVIRONMENT"
log_info "Location:             $LOCATION"
log_info "Subscription:         $SUBSCRIPTION_ID"
log_info "Resource Group:       $RESOURCE_GROUP"
log_info "VNet:                 $VNET_NAME"
log_info "VNet Address Prefix:  $VNET_ADDRESS_PREFIX"
log_info "App Gateway:          $AGW_NAME"
log_info "Public IP:            $AGW_PIP_NAME"
log_info "Key Vault:            $KV_NAME"
log_info "Container Registry:   $ACR_NAME"
log_info "======================================================"

# Login to Azure
azure_login

# Set Azure subscription
log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

# 1. Create Resource Group (if not exists)
log_info "Checking if resource group exists: $RESOURCE_GROUP"
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created resource group: $RESOURCE_GROUP"
else
    log_info "Resource group already exists: $RESOURCE_GROUP"
fi

# 2. Create Virtual Network
log_info "Checking if VNet exists: $VNET_NAME"
if ! az network vnet show --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    log_info "Creating VNet: $VNET_NAME"
    az network vnet create \
        --name "$VNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --address-prefixes "$VNET_ADDRESS_PREFIX" \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created VNet: $VNET_NAME"
else
    log_info "VNet already exists: $VNET_NAME"
fi

# 3. Create Subnets
log_info "Creating Application Gateway subnet: $APPGTWY_SUBNET_NAME"
if ! az network vnet subnet show --name "$APPGTWY_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$APPGTWY_SUBNET_NAME" \
        --address-prefixes "$APPGTWY_SUBNET_PREFIX" \
        --output table
    log_success "Created Application Gateway subnet: $APPGTWY_SUBNET_NAME"
else
    log_info "Application Gateway subnet already exists: $APPGTWY_SUBNET_NAME"
fi

log_info "Creating NBRLY Container App Environment subnet: $NBRLY_SUBNET_NAME"
if ! az network vnet subnet show --name "$NBRLY_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$NBRLY_SUBNET_NAME" \
        --address-prefixes "$NBRLY_SUBNET_PREFIX" \
        --output table
    log_success "Created NBRLY CAE subnet: $NBRLY_SUBNET_NAME"
else
    log_info "NBRLY CAE subnet already exists: $NBRLY_SUBNET_NAME"
fi

log_info "Creating BLOOM Container App Environment subnet: $BLOOM_SUBNET_NAME"
if ! az network vnet subnet show --name "$BLOOM_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$BLOOM_SUBNET_NAME" \
        --address-prefixes "$BLOOM_SUBNET_PREFIX" \
        --output table
    log_success "Created BLOOM CAE subnet: $BLOOM_SUBNET_NAME"
else
    log_info "BLOOM CAE subnet already exists: $BLOOM_SUBNET_NAME"
fi

log_info "Creating Private Endpoint subnet: $PE_SUBNET_NAME"
if ! az network vnet subnet show --name "$PE_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$PE_SUBNET_NAME" \
        --address-prefixes "$PE_SUBNET_PREFIX" \
        --output table
    log_success "Created Private Endpoint subnet: $PE_SUBNET_NAME"
else
    log_info "Private Endpoint subnet already exists: $PE_SUBNET_NAME"
fi

# 4. Create Container Registry
log_info "Creating Container Registry: $ACR_NAME"
if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az acr create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACR_NAME" \
        --sku Basic \
        --location "$LOCATION" \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created Container Registry: $ACR_NAME"
else
    log_info "Container Registry already exists: $ACR_NAME"
fi

# 5. Create Key Vault
log_info "Creating Key Vault: $KV_NAME"
if ! az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az keyvault create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$KV_NAME" \
        --location "$LOCATION" \
        --enable-rbac-authorization true \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created Key Vault: $KV_NAME"
else
    log_info "Key Vault already exists: $KV_NAME"
fi

# 6. Assign RBAC roles for Key Vault operations
log_info "Assigning Key Vault RBAC roles to current user/service principal"
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [ -z "$CURRENT_USER_ID" ]; then
    # If not a user, get the service principal object ID
    CURRENT_USER_ID=$(az account show --query user.name -o tsv | xargs -I {} az ad sp show --id {} --query id -o tsv 2>/dev/null || echo "")
fi

if [ -n "$CURRENT_USER_ID" ]; then
    KV_ID=$(az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
    
    # Check and assign Key Vault Certificates Officer role
    if ! az role assignment list --assignee "$CURRENT_USER_ID" --role "Key Vault Certificates Officer" --scope "$KV_ID" --query "[0].id" -o tsv &>/dev/null; then
        log_info "Assigning 'Key Vault Certificates Officer' role"
        az role assignment create --assignee "$CURRENT_USER_ID" --role "Key Vault Certificates Officer" --scope "$KV_ID"
        log_success "Assigned 'Key Vault Certificates Officer' role"
        sleep 10
    else
        log_info "Current principal already has 'Key Vault Certificates Officer' role"
    fi
    
    # Check and assign Key Vault Secrets Officer role
    if ! az role assignment list --assignee "$CURRENT_USER_ID" --role "Key Vault Secrets Officer" --scope "$KV_ID" --query "[0].id" -o tsv &>/dev/null; then
        log_info "Assigning 'Key Vault Secrets Officer' role"
        az role assignment create --assignee "$CURRENT_USER_ID" --role "Key Vault Secrets Officer" --scope "$KV_ID"
        log_success "Assigned 'Key Vault Secrets Officer' role"
    else
        log_info "Current principal already has 'Key Vault Secrets Officer' role"
    fi
else
    log_warning "Could not determine current user/service principal ID for RBAC assignment"
fi

# 4. Certificate Management (skip if already exists)
CERT_NAME=$(parse_config "$INFRA_FILE" ".certificates.wildcard.certificateName")
log_info "Certificate name from config: $CERT_NAME"

# Check if certificate already exists in Key Vault
log_info "Checking if SSL certificate exists in Key Vault: $CERT_NAME"
if az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" &>/dev/null; then
    log_info "SSL certificate already exists in Key Vault: $CERT_NAME"
    CERT_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "id" -o tsv)
    CERT_SECRET_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "sid" -o tsv)
else
    log_warning "SSL certificate not found in Key Vault. Please ensure certificate is uploaded manually."
    log_info "Expected certificate name: $CERT_NAME"
    # Set placeholder values
    CERT_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME/certificates/$CERT_NAME"
    CERT_SECRET_ID="https://$KV_NAME.vault.azure.net/secrets/$CERT_NAME"
fi
    
    certId=$(az keyvault certificate import \
      --vault-name "$kvName" \
      --name "$certName" \
      --file "$certFilePath" \
      --password "$certPassword" \
      --query "id" -o tsv)
else
    log_info "SSL certificate already exists in Key Vault: $certName"
    certId=$(az keyvault certificate show --vault-name "$kvName" --name "$certName" --query "id" -o tsv || true)
fi

# Get the secret ID for Application Gateway (App Gateway needs the secret, not the certificate)
log_info "Retrieving secret ID for Application Gateway"
certSecretId=$(az keyvault certificate show --vault-name "$kvName" --name "$certName" --query "sid" -o tsv || true)

jq --arg certName "$certName" --arg certId "$certId" --arg certSecretId "$certSecretId" \
   '.common += {certificateName: $certName, certificateId: $certId, certificateSecretId: $certSecretId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg certName "$certName" --arg certId "$certId" --arg certSecretId "$certSecretId" \
   '.resources += {certificate: {name: $certName, id: $certId, secretId: $certSecretId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

# 7. Create Public IP for Application Gateway
log_info "Creating Public IP for Application Gateway: $AGW_PIP_NAME"
if ! az network public-ip show --name "$AGW_PIP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network public-ip create \
        --name "$AGW_PIP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --allocation-method Static \
        --sku Standard \
        --location "$LOCATION" \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created Public IP: $AGW_PIP_NAME"
else
    log_info "Public IP already exists: $AGW_PIP_NAME"
fi

# 8. Create Managed Identity for Application Gateway
AGW_UAMI_NAME="agw-managed-identity"
log_info "Creating Managed Identity for Application Gateway: $AGW_UAMI_NAME"
if ! az identity show --name "$AGW_UAMI_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az identity create \
        --name "$AGW_UAMI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created Managed Identity: $AGW_UAMI_NAME"
    # Wait for identity to be ready
    sleep 30
else
    log_info "Managed Identity already exists: $AGW_UAMI_NAME"
fi

AGW_UAMI_PRINCIPAL_ID=$(az identity show --name "$AGW_UAMI_NAME" --resource-group "$RESOURCE_GROUP" --query "principalId" -o tsv)

# 9. Assign Key Vault RBAC roles to Application Gateway Managed Identity
log_info "Assigning Key Vault RBAC roles to Application Gateway Managed Identity"
KV_ID=$(az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)

# Assign Key Vault Secrets User role
if ! az role assignment list --assignee "$AGW_UAMI_PRINCIPAL_ID" --role "Key Vault Secrets User" --scope "$KV_ID" --query "[0].id" -o tsv &>/dev/null; then
    log_info "Assigning 'Key Vault Secrets User' role to App Gateway Managed Identity"
    az role assignment create \
        --assignee "$AGW_UAMI_PRINCIPAL_ID" \
        --role "Key Vault Secrets User" \
        --scope "$KV_ID"
    log_success "Assigned 'Key Vault Secrets User' role"
else
    log_info "App Gateway Managed Identity already has 'Key Vault Secrets User' role"
fi

# Assign Key Vault Certificate User role
if ! az role assignment list --assignee "$AGW_UAMI_PRINCIPAL_ID" --role "Key Vault Certificate User" --scope "$KV_ID" --query "[0].id" -o tsv &>/dev/null; then
    log_info "Assigning 'Key Vault Certificate User' role to App Gateway Managed Identity"
    az role assignment create \
        --assignee "$AGW_UAMI_PRINCIPAL_ID" \
        --role "Key Vault Certificate User" \
        --scope "$KV_ID"
    log_success "Assigned 'Key Vault Certificate User' role"
else
    log_info "App Gateway Managed Identity already has 'Key Vault Certificate User' role"
fi

# 10. Create Application Gateway (basic configuration)
log_info "Creating Application Gateway: $AGW_NAME (this may take several minutes)"
AGW_UAMI_ID=$(az identity show --name "$AGW_UAMI_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)

if ! az network application-gateway show --name "$AGW_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network application-gateway create \
        --name "$AGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --vnet-name "$VNET_NAME" \
        --subnet "$APPGTWY_SUBNET_NAME" \
        --public-ip-address "$AGW_PIP_NAME" \
        --sku WAF_v2 \
        --capacity 1 \
        --http-settings-cookie-based-affinity Disabled \
        --frontend-port 80 \
        --http-settings-port 80 \
        --http-settings-protocol Http \
        --routing-rule-type Basic \
        --identity "$AGW_UAMI_ID" \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created Application Gateway: $AGW_NAME"
else
    log_info "Application Gateway already exists: $AGW_NAME"
fi

# 11. Configure SSL Certificate (if available)
if [ -n "$CERT_SECRET_ID" ] && [ "$CERT_SECRET_ID" != "null" ]; then
    log_info "Configuring SSL certificate from Key Vault: $CERT_NAME"
    
    # Check if SSL certificate is already added to Application Gateway
    if ! az network application-gateway ssl-cert show --gateway-name "$AGW_NAME" --resource-group "$RESOURCE_GROUP" --name "$CERT_NAME" &>/dev/null; then
        log_info "Adding SSL certificate to Application Gateway"
        az network application-gateway ssl-cert create \
            --gateway-name "$AGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CERT_NAME" \
            --key-vault-secret-id "$CERT_SECRET_ID"
        log_success "Added SSL certificate to Application Gateway"
    else
        log_info "SSL certificate already configured in Application Gateway"
    fi
    
    # Create frontend port for HTTPS
    if ! az network application-gateway frontend-port show --gateway-name "$AGW_NAME" --resource-group "$RESOURCE_GROUP" --name "port_443" &>/dev/null; then
        log_info "Creating HTTPS frontend port (443)"
        az network application-gateway frontend-port create \
            --gateway-name "$AGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "port_443" \
            --port 443
        log_success "Created HTTPS frontend port"
    else
        log_info "HTTPS frontend port already exists"
    fi
else
    log_warning "SSL certificate not available. HTTPS configuration skipped."
fi

# 12. Create Private Link Service for Application Gateway
log_info "Creating Private Link Service for Application Gateway: ${AGW_NAME}-pls"
PLS_NAME="${AGW_NAME}-pls"
AGW_FRONTEND_IP_ID=$(az network application-gateway show \
    --name "$AGW_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "frontendIPConfigurations[0].id" -o tsv)

if ! az network private-link-service show --name "$PLS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network private-link-service create \
        --name "$PLS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --vnet-name "$VNET_NAME" \
        --subnet "$APPGTWY_SUBNET_NAME" \
        --lb-frontend-ip-configs "$AGW_FRONTEND_IP_ID" \
        --visibility "All" \
        --auto-approval "All" \
        --fqdns "$AGW_NAME" \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created Private Link Service: $PLS_NAME"
else
    log_info "Private Link Service already exists: $PLS_NAME"
fi
log_info "============================================================================"
log_info "Common infrastructure deployment completed successfully"
log_info "============================================================================"
log_info "Next steps:"
log_info "1. Run 02-deploy-tenant-infra.sh for each tenant (nbrly, bloom)"
log_info "2. Run 03-deploy-tenant-resources.sh for Container Apps"
log_info "3. Configure Application Gateway routing with 04-configure-routing.sh"
log_info "============================================================================"
