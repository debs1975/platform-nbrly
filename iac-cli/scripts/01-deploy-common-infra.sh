#!/bin/bash

# -----------------------------------------------------------------------------
# SCRIPT: 01-deploy-common-infra.sh
# -----------------------------------------------------------------------------
# DESCRIPTION:
#   Deploys shared infrastructure components required for the Astra platform.
#   This script provisions common resources that must be deployed before 
#   environment-specific infrastructure.
#
# USAGE:
#   ./01-deploy-common-infra.sh [ENVIRONMENT]
#
# PARAMETERS:
#   ENVIRONMENT    (Optional) Target deployment environment
#                  Valid values: dev, stage, prod
#                  Default: dev
#
# EXAMPLES:
#   # Deploy to development environment (default)
#   ./01-deploy-common-infra.sh
#
#   # Deploy to staging environment
#   ./01-deploy-common-infra.sh stage
#
#   # Deploy to production environment
#   ./01-deploy-common-infra.sh prod
#
# PREREQUISITES:
#   - Valid cloud provider credentials configured
#   - Appropriate IAM permissions for infrastructure deployment
#   - Configuration variables reviewed and updated as needed
#
# EXIT CODES:
#   0 - Successful deployment
#   1 - Invalid environment parameter or deployment failure
# -----------------------------------------------------------------------------

set -euo pipefail

# Script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Get environment parameter (default to dev if not provided)
ENV=${1:-dev}

# Validate environment
if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
    echo "ERROR: Invalid environment: $ENV"
    echo "Usage: ./01-deploy-common-infra.sh [dev|stage|prod]"
    exit 1
fi

# Configuration files
CONFIG_DIR="$PROJECT_ROOT/config"
PARAMETERS_FILE="$CONFIG_DIR/parameters-${ENV}.json"
INFRA_FILE="$CONFIG_DIR/infra-${ENV}.json"

# Source helper functions
source "$SCRIPT_DIR/helpers/logging.sh"
source "$SCRIPT_DIR/helpers/config-parser.sh"
source "$SCRIPT_DIR/helpers/azure-login.sh"

# Setup logging
setup_logging "common-infra" "$ENV"

# Trap errors
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

log_info "Starting common infrastructure deployment"
log_info "Using parameters: $PARAMETERS_FILE"
log_info "Using infrastructure: $INFRA_FILE"

# Validate parameters file exists
if [ ! -f "$PARAMETERS_FILE" ]; then
    log_error "Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

# Create infra-<env>.json if it doesn't exist
if [ ! -f "$INFRA_FILE" ]; then
    log_info "Infrastructure file not found: $INFRA_FILE"
    log_info "Creating infrastructure file from template..."
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$INFRA_FILE")"
    
    # Create a baseline infra-<env>.json file
    cat > "$INFRA_FILE" << 'EOF'
{
  "environment": "",
  "location": "",
  "subscription": {
    "id": ""
  },
  "resourceGroup": {
    "name": ""
  },
  "networking": {
    "virtualNetwork": {
      "name": "",
      "addressPrefixes": [
        "10.0.0.0/16"
      ]
    },
    "subnets": {
      "appGateway": {
        "name": "",
        "addressPrefix": "10.0.1.0/24"
      },
      "nbrlyCAE": {
        "name": "",
        "addressPrefix": "10.0.2.0/24"
      },
      "bloomCAE": {
        "name": "",
        "addressPrefix": "10.0.3.0/24"
      },
      "privateEndpoint": {
        "name": "",
        "addressPrefix": "10.0.4.0/24"
      }
    }
  },
  "applicationGateway": {
    "name": "",
    "publicIPAddress": {
      "name": ""
    }
  },
  "keyVault": {
    "name": ""
  },
  "containerRegistry": {
    "name": ""
  }
}
EOF
    
    log_warning "Infrastructure file created at: $INFRA_FILE"
    log_warning "Please review and update the configuration values in: $INFRA_FILE"
    log_info "At minimum, you must populate the following fields:"
    log_info "  - subscription.id"
    log_info "  - resourceGroup.name"
    log_info "  - networking.virtualNetwork.name"
    log_info "  - networking.subnets.appGateway.name"
    log_info "  - networking.subnets.nbrlyCAE.name"
    log_info "  - networking.subnets.bloomCAE.name"
    log_info "  - networking.subnets.privateEndpoint.name"
    log_info "  - applicationGateway.name"
    log_info "  - applicationGateway.publicIPAddress.name"
    log_info "  - keyVault.name"
    log_info "  - containerRegistry.name"
    log_error "Cannot proceed without valid infrastructure configuration."
    exit 1
fi

# Parse configuration from our reverse-engineered files
ENVIRONMENT=$(parse_config "$PARAMETERS_FILE" ".environment")
LOCATION=$(parse_config "$PARAMETERS_FILE" ".resourceGroup.location")
PROJECT=$(parse_config "$PARAMETERS_FILE" ".project")
REGION=$(parse_config "$PARAMETERS_FILE" ".region")
SUBSCRIPTION_ID=$(parse_config "$INFRA_FILE" ".subscription.id")
RESOURCE_GROUP=$(parse_config "$INFRA_FILE" ".resourceGroup.name")

# Validate critical configuration values
if [ -z "$RESOURCE_GROUP" ] || [ "$RESOURCE_GROUP" = "null" ]; then
    log_error "Resource group name is not configured in $INFRA_FILE"
    log_error "Please set the 'resourceGroup.name' field in $INFRA_FILE"
    exit 1
fi

if [ -z "$LOCATION" ]; then
    log_error "Location is not configured in $PARAMETERS_FILE"
    exit 1
fi

# Virtual Network configuration (from parameters - input for creation)
VNET_NAME=$(parse_config "$PARAMETERS_FILE" ".networking.vnet.name")
VNET_ADDRESS_PREFIX=$(parse_config "$PARAMETERS_FILE" ".networking.vnet.addressSpace")

# Subnet configurations (from parameters - input for creation)
APPGTWY_SUBNET_NAME=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.applicationGateway.name")
APPGTWY_SUBNET_PREFIX=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.applicationGateway.addressPrefix")

NBRLY_SUBNET_NAME=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.nbrly.name")
NBRLY_SUBNET_PREFIX=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.nbrly.addressPrefix")

BLOOM_SUBNET_NAME=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.bloom.name")
BLOOM_SUBNET_PREFIX=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.bloom.addressPrefix")

# Private Endpoint Subnet configuration (from parameters - input for creation)
PE_SUBNET_NAME=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.privateEndpoints.name")
PE_SUBNET_PREFIX=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.privateEndpoints.addressPrefix")

# Bastion Subnet configuration (from parameters - input for creation)
BASTION_SUBNET_NAME=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.bastion.name")
BASTION_SUBNET_PREFIX=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.bastion.addressPrefix")

# Postgres Subnet configuration (from parameters - input for creation)
POSTGRES_SUBNET_NAME=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.postgres.name")
POSTGRES_SUBNET_PREFIX=$(parse_config "$PARAMETERS_FILE" ".networking.subnets.postgres.addressPrefix")

# Application Gateway configuration (from parameters - input for creation)
AGW_NAME=$(parse_config "$PARAMETERS_FILE" ".applicationGateway.name")
AGW_PIP_NAME=$(parse_config "$PARAMETERS_FILE" ".applicationGateway.publicIP.name")

# Key Vault configuration (from parameters - input for creation)
KV_NAME=$(parse_config "$PARAMETERS_FILE" ".keyVault.name")

# Container Registry configuration (from parameters - input for creation)
ACR_NAME=$(parse_config "$PARAMETERS_FILE" ".containerRegistry.name")

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

# Initialize the generated infrastructure file (always reset this)
log_info "Initializing generated infrastructure file: $output_file"
echo '{}' | jq '.common = {} | .tenants = {}' > "$output_file"

# Only initialize the infrastructure config file on first creation
if [ ! -f "$infra_file" ]; then
    log_info "Initializing infrastructure tracking file: $infra_file"
    echo '{}' | jq '.project = $project | .environment = $env | .resources = {}' \
      --arg project "$PROJECT" --arg env "$ENV" > "$infra_file"
fi

# Derive all resource names from project and environment
rgName="${PROJECT}-${ENV}-${REGION}-rg"
vnetName="${PROJECT}-${ENV}-${REGION}-vnet"
agwName="${PROJECT}-${ENV}-${REGION}-agw"
pipName="${PROJECT}-${ENV}-${REGION}-pip"
kvName="${PROJECT}${ENV}${REGION}kv" # Key Vault names have restrictions
acrName="${PROJECT}${ENV}${REGION}acr" # ACR names have restrictions
lawName="${PROJECT}-${ENV}-${REGION}-law"
agwUamiName="${PROJECT}-${ENV}-${REGION}-agw-identity" # Managed identity for the AGW

# Print all inferred variables before deployment
log_info "╔══════════════════════════════════════════════════════════════════════════════╗"
log_info "║                    INFRASTRUCTURE DEPLOYMENT PARAMETERS                      ║"
log_info "╠══════════════════════════════════════════════════════════════════════════════╣"
log_info "║                                                                              ║"
log_info "║ ENVIRONMENT DETAILS:                                                         ║"
log_info "║   Environment:           $ENVIRONMENT"
log_info "║   Location:              $LOCATION"
log_info "║   Subscription ID:       $SUBSCRIPTION_ID"
log_info "║                                                                              ║"
log_info "║ RESOURCE GROUP:                                                              ║"
log_info "║   Name:                  $RESOURCE_GROUP"
log_info "║                                                                              ║"
log_info "║ NETWORKING:                                                                  ║"
log_info "║   Virtual Network:       $VNET_NAME"
log_info "║   Address Space:         $VNET_ADDRESS_PREFIX"
log_info "║   AppGateway Subnet:     $APPGTWY_SUBNET_NAME ($APPGTWY_SUBNET_PREFIX)"
log_info "║   Nbrly CAE Subnet:      $NBRLY_SUBNET_NAME ($NBRLY_SUBNET_PREFIX)"
log_info "║   Bloom CAE Subnet:      $BLOOM_SUBNET_NAME ($BLOOM_SUBNET_PREFIX)"
log_info "║   PrivateEndpoints:      $PE_SUBNET_NAME ($PE_SUBNET_PREFIX)"
log_info "║   Bastion Subnet:        $BASTION_SUBNET_NAME ($BASTION_SUBNET_PREFIX)"
log_info "║   Postgres Subnet:       $POSTGRES_SUBNET_NAME ($POSTGRES_SUBNET_PREFIX)"
log_info "║                                                                              ║"
log_info "║ APPLICATION GATEWAY:                                                         ║"
log_info "║   Name:                  $AGW_NAME"
log_info "║   Public IP:             $AGW_PIP_NAME"
log_info "║                                                                              ║"
log_info "║ SECURITY & STORAGE:                                                          ║"
log_info "║   Key Vault:             $KV_NAME"
log_info "║   Container Registry:    $ACR_NAME"
log_info "║                                                                              ║"
log_info "╚══════════════════════════════════════════════════════════════════════════════╝"

log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Starting Common Infrastructure Deployment for $ENVIRONMENT environment"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info ""

# Login to Azure
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
log_info "│ STEP 1: Creating Resource Group                                              │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Resource Group Configuration:"
log_info "    • Name:        $RESOURCE_GROUP"
log_info "    • Location:    $LOCATION"
log_info "    • Environment: $ENVIRONMENT"
log_info "    • Project:     astra"
log_info ""

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

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 2: Creating Virtual Network                                             │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Virtual Network Configuration:"
log_info "    • Name:         $VNET_NAME"
log_info "    • Location:     $LOCATION"
log_info "    • Address Space: $VNET_ADDRESS_PREFIX"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info ""

log_info "" 
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 3: Creating Subnets                                                     │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Subnets to Create:"
log_info "    • Application Gateway: $APPGTWY_SUBNET_NAME ($APPGTWY_SUBNET_PREFIX)"
log_info "    • NBRLY CAE:          $NBRLY_SUBNET_NAME ($NBRLY_SUBNET_PREFIX)"
log_info "    • Bloom CAE:          $BLOOM_SUBNET_NAME ($BLOOM_SUBNET_PREFIX)"
log_info "    • Bastion:            $BASTION_SUBNET_NAME ($BASTION_SUBNET_PREFIX)"
log_info "    • PostgreSQL:         $POSTGRES_SUBNET_NAME ($POSTGRES_SUBNET_PREFIX)"
log_info "    • Private Endpoints:  $PE_SUBNET_NAME ($PE_SUBNET_PREFIX)"
log_info ""

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
        --delegations Microsoft.App/environments \
        --output table
    log_success "Created NBRLY CAE subnet: $NBRLY_SUBNET_NAME"
    log_info "Delegated subnet to Microsoft.App/environments"
else
    log_info "NBRLY CAE subnet already exists: $NBRLY_SUBNET_NAME"
    # Check and add delegation if missing
    DELEGATION_EXISTS=$(az network vnet subnet show --name "$NBRLY_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" --query "delegations[?serviceName=='Microsoft.App/environments'].name" -o tsv)
    if [ -z "$DELEGATION_EXISTS" ]; then
        log_info "Adding delegation to Microsoft.App/environments"
        az network vnet subnet update \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$NBRLY_SUBNET_NAME" \
            --delegations Microsoft.App/environments \
            --output none
        log_success "Added delegation to Microsoft.App/environments"
    else
        log_info "Subnet already delegated to Microsoft.App/environments"
    fi
fi

log_info "Creating BLOOM Container App Environment subnet: $BLOOM_SUBNET_NAME"
if ! az network vnet subnet show --name "$BLOOM_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$BLOOM_SUBNET_NAME" \
        --address-prefixes "$BLOOM_SUBNET_PREFIX" \
        --delegations Microsoft.App/environments \
        --output table
    log_success "Created BLOOM CAE subnet: $BLOOM_SUBNET_NAME"
    log_info "Delegated subnet to Microsoft.App/environments"
else
    log_info "BLOOM CAE subnet already exists: $BLOOM_SUBNET_NAME"
    # Check and add delegation if missing
    DELEGATION_EXISTS=$(az network vnet subnet show --name "$BLOOM_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" --query "delegations[?serviceName=='Microsoft.App/environments'].name" -o tsv)
    if [ -z "$DELEGATION_EXISTS" ]; then
        log_info "Adding delegation to Microsoft.App/environments"
        az network vnet subnet update \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$BLOOM_SUBNET_NAME" \
            --delegations Microsoft.App/environments \
            --output none
        log_success "Added delegation to Microsoft.App/environments"
    else
        log_info "Subnet already delegated to Microsoft.App/environments"
    fi
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

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 4: Creating Container Registry                                         │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Registry Configuration:"
log_info "    • Name:        $ACR_NAME"
log_info "    • Location:    $LOCATION"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • SKU:         Basic"
log_info ""

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

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 5: Creating Key Vault                                                   │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Key Vault Configuration:"
log_info "    • Name:         $KV_NAME"
log_info "    • Location:     $LOCATION"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • Authorization: RBAC Enabled"
log_info ""

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

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 5.5: Assigning RBAC Roles for Key Vault Operations                     │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""

# 6. Assign RBAC roles for Key Vault operations
log_info "Assigning Key Vault RBAC roles to current user/service principal"
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
CURRENT_USER_NAME=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "")
if [ -z "$CURRENT_USER_ID" ]; then
    # If not a user, get the service principal object ID and display name
    CURRENT_USER_NAME=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
    CURRENT_USER_ID=$(az ad sp show --id "$CURRENT_USER_NAME" --query id -o tsv 2>/dev/null || echo "")
    # Get the service principal display name if available
    if [ -n "$CURRENT_USER_ID" ]; then
        SP_DISPLAY_NAME=$(az ad sp show --id "$CURRENT_USER_ID" --query displayName -o tsv 2>/dev/null || echo "")
        if [ -n "$SP_DISPLAY_NAME" ]; then
            CURRENT_USER_NAME="$SP_DISPLAY_NAME ($CURRENT_USER_NAME)"
        fi
    fi
fi

log_info "  RBAC Role Assignment Configuration:"
log_info "    • Key Vault:             $KV_NAME"
log_info "    • Current User:          $CURRENT_USER_NAME"
log_info "    • Roles to Assign:       Certificates Officer, Secrets Officer, Certificate User, Secrets User"
log_info "    • Target:                Current User/Service Principal"
log_info ""

if [ -n "$CURRENT_USER_ID" ]; then
    KV_ID=$(az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
    ROLES_ASSIGNED=false
    
    # Check and assign Key Vault Certificates Officer role
    CERT_OFFICER_ROLE_EXISTS=$(az role assignment list --assignee "$CURRENT_USER_ID" --role "Key Vault Certificates Officer" --scope "$KV_ID" 2>/dev/null | jq -r 'length')
    if [ "$CERT_OFFICER_ROLE_EXISTS" -eq 0 ]; then
        log_info "Assigning 'Key Vault Certificates Officer' role"
        az role assignment create --assignee "$CURRENT_USER_ID" --role "Key Vault Certificates Officer" --scope "$KV_ID"
        log_success "Assigned 'Key Vault Certificates Officer' role"
        ROLES_ASSIGNED=true
    else
        log_info "Current principal already has 'Key Vault Certificates Officer' role"
    fi
    
    # Check and assign Key Vault Secrets Officer role
    SECRETS_OFFICER_ROLE_EXISTS=$(az role assignment list --assignee "$CURRENT_USER_ID" --role "Key Vault Secrets Officer" --scope "$KV_ID" 2>/dev/null | jq -r 'length')
    if [ "$SECRETS_OFFICER_ROLE_EXISTS" -eq 0 ]; then
        log_info "Assigning 'Key Vault Secrets Officer' role"
        az role assignment create --assignee "$CURRENT_USER_ID" --role "Key Vault Secrets Officer" --scope "$KV_ID"
        log_success "Assigned 'Key Vault Secrets Officer' role"
        ROLES_ASSIGNED=true
    else
        log_info "Current principal already has 'Key Vault Secrets Officer' role"
    fi
    
    # Check and assign Key Vault Certificate User role (for reading certificates)
    CERT_USER_ROLE_EXISTS=$(az role assignment list --assignee "$CURRENT_USER_ID" --role "Key Vault Certificate User" --scope "$KV_ID" 2>/dev/null | jq -r 'length')
    if [ "$CERT_USER_ROLE_EXISTS" -eq 0 ]; then
        log_info "Assigning 'Key Vault Certificate User' role"
        az role assignment create --assignee "$CURRENT_USER_ID" --role "Key Vault Certificate User" --scope "$KV_ID"
        log_success "Assigned 'Key Vault Certificate User' role"
        ROLES_ASSIGNED=true
    else
        log_info "Current principal already has 'Key Vault Certificate User' role"
    fi
    
    # Check and assign Key Vault Secrets User role (for reading secrets)
    SECRETS_USER_ROLE_EXISTS=$(az role assignment list --assignee "$CURRENT_USER_ID" --role "Key Vault Secrets User" --scope "$KV_ID" 2>/dev/null | jq -r 'length')
    if [ "$SECRETS_USER_ROLE_EXISTS" -eq 0 ]; then
        log_info "Assigning 'Key Vault Secrets User' role"
        az role assignment create --assignee "$CURRENT_USER_ID" --role "Key Vault Secrets User" --scope "$KV_ID"
        log_success "Assigned 'Key Vault Secrets User' role"
        ROLES_ASSIGNED=true
    else
        log_info "Current principal already has 'Key Vault Secrets User' role"
    fi
    
    # Wait once at the end for all role assignments to propagate
    if [ "$ROLES_ASSIGNED" = true ]; then
        log_info "Waiting 60 seconds for all role assignment propagation..."
        log_info "Note: Azure RBAC can take up to 5 minutes to fully propagate in some cases"
        sleep 60
    fi
    
    log_info "All RBAC role assignments completed successfully"
else
    log_warning "Could not determine current user/service principal ID for RBAC assignment"
fi

# Additional wait to ensure Key Vault RBAC is fully propagated before certificate operations
log_info ""
log_info "Waiting 30 additional seconds to ensure Key Vault RBAC permissions are fully propagated..."
log_info "This is critical for certificate read/write operations"
sleep 30

# Verify RBAC permissions are working before proceeding
log_info ""
log_info "Verifying Key Vault access permissions..."
if az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    log_success "Key Vault access confirmed - RBAC permissions are active"
else
    log_warning "Unable to verify Key Vault access - proceeding with caution"
fi

# 4. Certificate Management (skip if already exists)
CERT_NAME=$(parse_config "$PARAMETERS_FILE" ".certificates.wildcard.name")
log_info "Certificate name from config: $CERT_NAME"

# Check if certificate already exists in Key Vault with diagnostic output
log_info ""
log_info "Checking if SSL certificate exists in Key Vault: $CERT_NAME"
log_info "Key Vault Name: $KV_NAME"
log_info "Resource Group: $RESOURCE_GROUP"

# Try to check certificate with error output for debugging
CERT_CHECK_OUTPUT=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" 2>&1 || true)
CERT_CHECK_EXIT=$?

if [ $CERT_CHECK_EXIT -eq 0 ]; then
    log_info "SSL certificate already exists in Key Vault: $CERT_NAME"
    CERT_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "id" -o tsv 2>/dev/null || echo "")
    CERT_SECRET_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "sid" -o tsv 2>/dev/null || echo "")
    
    if [ -z "$CERT_ID" ] || [ -z "$CERT_SECRET_ID" ]; then
        log_warning "Failed to retrieve certificate details even though certificate exists"
        log_warning "This may be due to RBAC permission delays"
    else
        log_success "Certificate ID: $CERT_ID"
        log_success "Certificate Secret ID: $CERT_SECRET_ID"
    fi
elif echo "$CERT_CHECK_OUTPUT" | grep -q "Forbidden\|not authorized\|Access denied"; then
    log_warning "Permission error detected when checking certificate"
    log_warning "This is likely due to RBAC propagation delay"
    log_info ""
    log_info "Waiting an additional 60 seconds for RBAC propagation..."
    sleep 60
    log_info ""
    log_info "Retrying certificate check..."
    CERT_CHECK_OUTPUT=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" 2>&1 || true)
    CERT_CHECK_EXIT=$?
    
    if [ $CERT_CHECK_EXIT -eq 0 ]; then
        log_success "SSL certificate found after retry: $CERT_NAME"
        CERT_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "id" -o tsv 2>/dev/null || echo "")
        CERT_SECRET_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "sid" -o tsv 2>/dev/null || echo "")
        
        if [ -n "$CERT_ID" ] && [ -n "$CERT_SECRET_ID" ]; then
            log_success "Certificate ID: $CERT_ID"
            log_success "Certificate Secret ID: $CERT_SECRET_ID"
        fi
    else
        log_warning "SSL certificate still not accessible: $CERT_NAME"
        log_warning "Error details: $CERT_CHECK_OUTPUT"
    fi
else
    log_warning "SSL certificate not found in Key Vault: $CERT_NAME"
fi

# Only proceed with upload if certificate was not found
if [ $CERT_CHECK_EXIT -ne 0 ]; then
    log_info ""
    log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
    log_info "│ Attempting Automatic Certificate Upload from Credentials                     │"
    log_info "└──────────────────────────────────────────────────────────────────────────────┘"
    log_info ""
    
    # Load certificate configuration from parameters file
    CERT_FILE_PATH=$(parse_config "$PARAMETERS_FILE" ".certificates.wildcard.filePath")
    
    # Try to load certificate credentials from astrapiaio.json
    CREDS_FILE="$PROJECT_ROOT/creds/astrapiaio.json"
    if [ -f "$CREDS_FILE" ]; then
        log_info "Found credentials file: $CREDS_FILE"
        
        # Extract certificate password from credentials file
        CERT_PASSWORD=$(jq -r '.certificatePassword' "$CREDS_FILE" 2>/dev/null || echo "")
        
        if [ -n "$CERT_PASSWORD" ]; then
            log_info "Certificate credentials found in credentials file"
            log_info ""
            log_info "  Certificate Upload Configuration:"
            log_info "    • Certificate Name:  $CERT_NAME"
            log_info "    • Certificate Path:  $CERT_FILE_PATH"
            log_info "    • Key Vault:         $KV_NAME"
            log_info "    • Resource Group:    $RESOURCE_GROUP"
            log_info "    • Source:            Credentials file + Parameters file"
            log_info ""
            
            # Resolve certificate file path
            CERT_PATH=""
            if [[ "$CERT_FILE_PATH" == /* ]]; then
                # Absolute path
                CERT_PATH="$CERT_FILE_PATH"
            else
                # Relative path - resolve from PROJECT_ROOT
                # PROJECT_ROOT is the parent of SCRIPT_DIR (scripts folder)
                # So if CERT_FILE_PATH is ../creds/astrapiaiofullchain.pfx
                # and PROJECT_ROOT is /path/to/iac-cli
                # Then CERT_PATH should be /path/to/iac-cli/creds/astrapiaiofullchain.pfx
                CERT_PATH="$PROJECT_ROOT/$CERT_FILE_PATH"
            fi
            
            # Resolve .. in the path using a simple bash approach
            # This handles paths like /path/iac-cli/../creds/file.pfx -> /path/creds/file.pfx
            while [[ "$CERT_PATH" == *"/.."* ]]; do
                CERT_PATH="${CERT_PATH//\/..\//.\/}"
            done
            
            log_info "Resolved certificate path: $CERT_PATH"
            
            if [ -f "$CERT_PATH" ]; then
                log_info "Certificate file found at: $CERT_PATH"
                log_info "Uploading certificate to Key Vault..."
                
                # Capture both stdout and stderr for better error diagnostics
                UPLOAD_OUTPUT=$(az keyvault certificate import \
                    --vault-name "$KV_NAME" \
                    --name "$CERT_NAME" \
                    --file "$CERT_PATH" \
                    --password "$CERT_PASSWORD" \
                    2>&1 || true)
                UPLOAD_EXIT=$?
                
                if [ $UPLOAD_EXIT -eq 0 ]; then
                    log_success "Successfully uploaded certificate to Key Vault: $CERT_NAME"
                    sleep 10
                    log_info "Retrieving certificate details..."
                    CERT_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "id" -o tsv 2>/dev/null || echo "")
                    CERT_SECRET_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "sid" -o tsv 2>/dev/null || echo "")
                    log_success "Certificate ID: $CERT_ID"
                    log_success "Certificate Secret ID: $CERT_SECRET_ID"
                else
                    log_warning "Failed to upload certificate from file: $CERT_PATH"
                    log_warning "Error details:"
                    log_warning "$UPLOAD_OUTPUT"
                    
                    # Check if it's a permission error
                    if echo "$UPLOAD_OUTPUT" | grep -q "Forbidden\|not authorized\|Access denied"; then
                        log_warning "Permission error detected during certificate upload"
                        log_info ""
                        log_info "Waiting 60 additional seconds for RBAC permissions to propagate..."
                        sleep 60
                        log_info ""
                        log_info "Retrying certificate upload..."
                        
                        UPLOAD_OUTPUT=$(az keyvault certificate import \
                            --vault-name "$KV_NAME" \
                            --name "$CERT_NAME" \
                            --file "$CERT_PATH" \
                            --password "$CERT_PASSWORD" \
                            2>&1 || true)
                        UPLOAD_EXIT=$?
                        
                        if [ $UPLOAD_EXIT -eq 0 ]; then
                            log_success "Successfully uploaded certificate on retry: $CERT_NAME"
                            sleep 10
                            log_info "Retrieving certificate details..."
                            CERT_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "id" -o tsv 2>/dev/null || echo "")
                            CERT_SECRET_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "sid" -o tsv 2>/dev/null || echo "")
                            log_success "Certificate ID: $CERT_ID"
                            log_success "Certificate Secret ID: $CERT_SECRET_ID"
                        else
                            log_error "Certificate upload failed even after retry"
                            log_error "Error: $UPLOAD_OUTPUT"
                            log_info ""
                            log_info "Setting placeholder values - HTTPS configuration will be skipped"
                            CERT_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME/certificates/$CERT_NAME"
                            CERT_SECRET_ID="https://$KV_NAME.vault.azure.net/secrets/$CERT_NAME"
                        fi
                    else
                        log_info ""
                        log_info "Setting placeholder values - HTTPS configuration will be skipped"
                        CERT_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME/certificates/$CERT_NAME"
                        CERT_SECRET_ID="https://$KV_NAME.vault.azure.net/secrets/$CERT_NAME"
                    fi
                fi
                # Capture both stdout and stderr for better error diagnostics
                UPLOAD_OUTPUT=$(az keyvault certificate import \
                    --vault-name "$KV_NAME" \
                    --name "$CERT_NAME" \
                    --file "$CERT_PATH" \
                    --password "$CERT_PASSWORD" \
                    2>&1 || true)
                UPLOAD_EXIT=$?
                
                if [ $UPLOAD_EXIT -eq 0 ]; then
                    log_success "Successfully uploaded certificate to Key Vault: $CERT_NAME"
                    sleep 10
                    log_info "Retrieving certificate details..."
                    CERT_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "id" -o tsv 2>/dev/null || echo "")
                    CERT_SECRET_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "sid" -o tsv 2>/dev/null || echo "")
                    log_success "Certificate ID: $CERT_ID"
                    log_success "Certificate Secret ID: $CERT_SECRET_ID"
                else
                    log_warning "Failed to upload certificate from file: $CERT_PATH"
                    log_warning "Error details:"
                    log_warning "$UPLOAD_OUTPUT"
                    log_info ""
                    log_info "Setting placeholder values - HTTPS configuration will be skipped"
                    CERT_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME/certificates/$CERT_NAME"
                    CERT_SECRET_ID="https://$KV_NAME.vault.azure.net/secrets/$CERT_NAME"
                fi
            else
                log_warning "Certificate file not found: $CERT_PATH"
                log_info ""
                log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
                log_info "│ ACTION REQUIRED: Certificate File Not Found                                   │"
                log_info "└──────────────────────────────────────────────────────────────────────────────┘"
                log_info ""
                log_info "  Expected location: $CERT_PATH"
                log_info "  File path from config: $CERT_FILE_PATH"
                log_info ""
                log_info "  Please ensure the certificate file exists at the specified location"
                log_info "  Then re-run the script to upload the certificate."
                log_info "Continuing with placeholder values - HTTPS configuration will be skipped"
                log_info ""
                
                # Set placeholder values
                CERT_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME/certificates/$CERT_NAME"
                CERT_SECRET_ID="https://$KV_NAME.vault.azure.net/secrets/$CERT_NAME"
            fi
        else
            log_warning "Certificate password not found in credentials file"
            log_info "Setting placeholder values - HTTPS configuration will be skipped"
            CERT_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME/certificates/$CERT_NAME"
            CERT_SECRET_ID="https://$KV_NAME.vault.azure.net/secrets/$CERT_NAME"
        fi
    else
        log_warning "Credentials file not found: $CREDS_FILE"
        log_info ""
        log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
        log_info "│ ACTION REQUIRED: Manual Certificate Upload Required                          │"
        log_info "└──────────────────────────────────────────────────────────────────────────────┘"
        log_info ""
        log_info "  Certificate Details:"
        log_info "    • Certificate Name:  $CERT_NAME"
        log_info "    • Key Vault:         $KV_NAME"
        log_info "    • Resource Group:    $RESOURCE_GROUP"
        log_info ""
        log_info "  Instructions to upload certificate:"
        log_info ""
        log_info "  Option 1: Using Azure Portal"
        log_info "    1. Navigate to Key Vault: $KV_NAME"
        log_info "    2. Go to Certificates section"
        log_info "    3. Click 'Generate/Import' button"
        log_info "    4. Upload your PFX/PEM certificate file"
        log_info ""
        log_info "  Option 2: Using Azure CLI"
        log_info "    Run the following command:"
        log_info ""
        log_info "      az keyvault certificate import \\"
        log_info "      --vault-name $KV_NAME \\"
        log_info "      --name $CERT_NAME \\"
        log_info "      --file /path/to/certificate.pfx \\"
        log_info "      --password <certificate-password>"
        log_info ""
        log_info "  Waiting 60 seconds for manual certificate upload..."
        log_info "  (Press Ctrl+C to cancel and upload manually, then re-run the script)"
        log_info ""
        
        # Wait for manual upload
        for i in {60..1}; do
            echo -n "."
            sleep 1
        done
        echo ""
        log_info ""
        
        # Check again after waiting
        log_info "Checking again if certificate has been uploaded..."
        if az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" &>/dev/null; then
            log_success "SSL certificate found in Key Vault: $CERT_NAME"
            CERT_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "id" -o tsv)
            CERT_SECRET_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "sid" -o tsv)
        else
            log_warning "SSL certificate still not found in Key Vault after waiting period"
            log_warning "Please upload the certificate manually and re-run the script"
            log_warning "Continuing with placeholder values - HTTPS configuration will be skipped"
            log_info ""
            
            # Set placeholder values
            CERT_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME/certificates/$CERT_NAME"
            CERT_SECRET_ID="https://$KV_NAME.vault.azure.net/secrets/$CERT_NAME"
        fi
    fi
fi

# Get the secret ID for Application Gateway (App Gateway needs the secret, not the certificate)
log_info "Retrieving secret ID for Application Gateway"
CERT_SECRET_ID=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$CERT_NAME" --query "sid" -o tsv 2>/dev/null || echo "")

jq --arg certName "$CERT_NAME" --arg certId "$CERT_ID" --arg certSecretId "$CERT_SECRET_ID" \
   '.common += {certificateName: $certName, certificateId: $certId, certificateSecretId: $certSecretId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg certName "$CERT_NAME" --arg certId "$CERT_ID" --arg certSecretId "$CERT_SECRET_ID" \
   '.resources += {certificate: {name: $certName, id: $certId, secretId: $certSecretId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 6: Creating Public IP for Application Gateway                           │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Public IP Configuration:"
log_info "    • Name:         $AGW_PIP_NAME"
log_info "    • Location:     $LOCATION"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • Allocation:   Static"
log_info "    • SKU:          Standard"
log_info ""

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

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 7: Creating Managed Identity for Application Gateway                   │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Managed Identity Configuration:"
log_info "    • Name:         $agwUamiName"
log_info "    • Location:     $LOCATION"
log_info "    • Resource Grp: $RESOURCE_GROUP"
log_info "    • Purpose:      Key Vault Certificate Access for App Gateway"
log_info ""

# 8. Create Managed Identity for Application Gateway
AGW_UAMI_NAME="$agwUamiName"
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
log_info ""
log_info "  Assigning Key Vault RBAC Roles:"
log_info "    • Role 1: Key Vault Certificate User"
log_info "    • Role 2: Key Vault Secrets User"
log_info ""
log_info "Retrieving Key Vault ID..."
KV_ID=$(az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
log_info "Key Vault ID: $KV_ID"

# Track if we assigned any new roles
ASSIGNED_NEW_ROLES=false

# Assign Key Vault Certificate User role
CERT_USER_ROLE_EXISTS=$(az role assignment list --assignee "$AGW_UAMI_PRINCIPAL_ID" --role "Key Vault Certificate User" --scope "$KV_ID" 2>/dev/null | jq -r 'length')
if [ "$CERT_USER_ROLE_EXISTS" -eq 0 ]; then
    log_info "Assigning 'Key Vault Certificate User' role to App Gateway Managed Identity..."
    az role assignment create \
        --assignee "$AGW_UAMI_PRINCIPAL_ID" \
        --role "Key Vault Certificate User" \
        --scope "$KV_ID" \
        --output none
    log_success "Assigned 'Key Vault Certificate User' role"
    ASSIGNED_NEW_ROLES=true
else
    log_info "App Gateway Managed Identity already has 'Key Vault Certificate User' role"
fi

# Assign Key Vault Secrets User role
SECRETS_USER_ROLE_EXISTS=$(az role assignment list --assignee "$AGW_UAMI_PRINCIPAL_ID" --role "Key Vault Secrets User" --scope "$KV_ID" 2>/dev/null | jq -r 'length')
if [ "$SECRETS_USER_ROLE_EXISTS" -eq 0 ]; then
    log_info "Assigning 'Key Vault Secrets User' role to App Gateway Managed Identity..."
    az role assignment create \
        --assignee "$AGW_UAMI_PRINCIPAL_ID" \
        --role "Key Vault Secrets User" \
        --scope "$KV_ID" \
        --output none
    log_success "Assigned 'Key Vault Secrets User' role"
    ASSIGNED_NEW_ROLES=true
else
    log_info "App Gateway Managed Identity already has 'Key Vault Secrets User' role"
fi

# Wait for role assignments to propagate
if [ "$ASSIGNED_NEW_ROLES" = true ]; then
    log_info ""
    log_info "Waiting 30 seconds for RBAC role assignments to propagate..."
    sleep 30
    log_success "RBAC roles are now active"
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 8: Creating Application Gateway                                         │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  Application Gateway Configuration:"
log_info "    • Name:              $AGW_NAME"
log_info "    • Location:          $LOCATION"
log_info "    • Resource Grp:      $RESOURCE_GROUP"
log_info "    • Public IP:         $AGW_PIP_NAME"
log_info "    • Subnet:            $APPGTWY_SUBNET_NAME"
log_info "    • SKU:               Standard_v2"
log_info "    • Managed Identity:  $AGW_UAMI_NAME"
log_info "    • Note:              This may take several minutes"
log_info ""

# 10. Create Application Gateway (basic configuration)
log_info "Creating Application Gateway: $AGW_NAME (this may take several minutes)"
log_info "This will automatically be assigned the managed identity with Key Vault access"
AGW_UAMI_ID=$(az identity show --name "$AGW_UAMI_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)

if ! az network application-gateway show --name "$AGW_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az network application-gateway create \
        --name "$AGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --vnet-name "$VNET_NAME" \
        --subnet "$APPGTWY_SUBNET_NAME" \
        --public-ip-address "$AGW_PIP_NAME" \
        --sku Standard_v2 \
        --capacity 1 \
        --http-settings-cookie-based-affinity Disabled \
        --frontend-port 80 \
        --http-settings-port 80 \
        --http-settings-protocol Http \
        --routing-rule-type Basic \
        --priority 100 \
        --identity "$AGW_UAMI_ID" \
        --tags Environment="$ENVIRONMENT" Project="astra" \
        --output table
    log_success "Created Application Gateway: $AGW_NAME"
    log_success "Assigned Managed Identity: $AGW_UAMI_NAME (with Key Vault Certificate and Secrets User roles)"
else
    log_info "Application Gateway already exists: $AGW_NAME"
    
    # Ensure the correct managed identity is assigned (update if needed)
    log_info "Verifying managed identity assignment..."
    CURRENT_IDENTITY=$(az network application-gateway show --name "$AGW_NAME" --resource-group "$RESOURCE_GROUP" --query "identity.userAssignedIdentities" -o json 2>/dev/null || echo "{}")
    
    if ! echo "$CURRENT_IDENTITY" | jq -e "has(\"$AGW_UAMI_ID\")" &>/dev/null; then
        log_info "Updating Application Gateway managed identity to: $AGW_UAMI_NAME"
        az network application-gateway identity assign \
            --gateway-name "$AGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --identity "$AGW_UAMI_ID"
        log_success "Updated managed identity assignment"
    else
        log_info "Managed identity already correctly assigned: $AGW_UAMI_NAME"
    fi
fi

log_info ""
log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
log_info "│ STEP 8.5: Configuring SSL Certificate and HTTPS                             │"
log_info "└──────────────────────────────────────────────────────────────────────────────┘"
log_info ""
log_info "  SSL/TLS Configuration:"
log_info "    • Application Gateway: $AGW_NAME"
log_info "    • Certificate Name:    $CERT_NAME"
log_info "    • Key Vault:           $KV_NAME"
log_info "    • CERT_SECRET_ID:      $CERT_SECRET_ID"
log_info "    • Frontend Port:       443 (HTTPS)"
log_info ""

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
        log_info ""
        log_info "  Creating HTTPS Frontend Port:"
        log_info "    • Port Number:         443"
        log_info "    • Protocol:            HTTPS"
        log_info "    • Application Gateway: $AGW_NAME"
        log_info ""
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

# log_info ""
# log_info "┌──────────────────────────────────────────────────────────────────────────────┐"
# log_info "│ STEP 9: Creating Private Link Service                                        │"
# log_info "└──────────────────────────────────────────────────────────────────────────────┘"
# log_info ""
# log_info "  Private Link Service Configuration:"
# log_info "    • Name:         ${AGW_NAME}-pls"
# log_info "    • Location:     $LOCATION"
# log_info "    • Resource Grp: $RESOURCE_GROUP"
# log_info "    • Endpoint:     App Gateway Frontend IP"
# log_info "    • Subnet:       $APPGTWY_SUBNET_NAME"
# log_info ""

# 12. Create Private Link Service for Application Gateway
# COMMENTED OUT FOR NOW - Re-enable when needed
# log_info "Creating Private Link Service for Application Gateway: ${AGW_NAME}-pls"
# PLS_NAME="${AGW_NAME}-pls"
# 
# # Get Application Gateway frontend IP configuration ID
# AGW_FRONTEND_IP_ID=$(az network application-gateway show \
#     --name "$AGW_NAME" \
#     --resource-group "$RESOURCE_GROUP" \
#     --query "frontendIPConfigurations[0].id" -o tsv)
# 
# if ! az network private-link-service show --name "$PLS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
#     log_info "Creating Private Link Service using Application Gateway Frontend IP..."
#     log_info "Application Gateway Frontend IP Configuration ID: $AGW_FRONTEND_IP_ID"
#     
#     # Create Private Link Service directly using AGW frontend IP
#     az network private-link-service create \
#         --name "$PLS_NAME" \
#         --resource-group "$RESOURCE_GROUP" \
#         --location "$LOCATION" \
#         --vnet-name "$VNET_NAME" \
#         --subnet "$APPGTWY_SUBNET_NAME" \
#         --lb-frontend-ip-configs "$AGW_FRONTEND_IP_ID" \
#         --visibility "All" \
#         --auto-approval "All" \
#         --tags Environment="$ENVIRONMENT" Project="astra" \
#         --output table
#     log_success "Created Private Link Service: $PLS_NAME"
# else
#     log_info "Private Link Service already exists: $PLS_NAME"
# fi
log_info "============================================================================"
log_info "Common infrastructure deployment completed successfully"
log_info "============================================================================"
log_info "Next steps:"
log_info "1. Run 02-deploy-tenant-infra.sh for each tenant (nbrly, bloom)"
log_info "2. Run 03-deploy-tenant-resources.sh for Container Apps"
log_info "3. Configure Application Gateway routing with 04-configure-routing.sh"
log_info "============================================================================"
