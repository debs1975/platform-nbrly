#!/bin/bash
set -euo pipefail
# ============================================================================
# Script: 01-deploy-networking.sh
# Purpose: Deploy networking infrastructure for nbrly environment
# Layer: 1 - Networking (VNet, Subnets, NSG, Private DNS)
# 
# Usage:
# ./scripts/01-deploy-networking.sh [environment]
#
# Arguments:
# environment (optional) - Environment name (dev, staging, prod)
# Defaults to "dev"
#
# Examples:
# ./scripts/01-deploy-networking.sh dev
# ./scripts/01-deploy-networking.sh prod
# ============================================================================
# Color codes for output
# Default environment
ENVIRONMENT="${1:-dev}"
# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/parameters-${ENVIRONMENT}.json"
# Setup logging
source "${SCRIPT_DIR}/helpers/logging.sh"
setup_logging "01-deploy-networking" "$ENVIRONMENT"
# Trap to ensure logging is finalized on exit
trap 'finalize_logging $?' EXIT
log_info "=========================================="
log_info "Layer 1: Networking Infrastructure"
log_info "Environment: ${ENVIRONMENT}"
log_info "=========================================="
echo ""
# Validate configuration file
if [ ! -f "$CONFIG_FILE" ]; then
 echo "❌ Configuration file not found: $CONFIG_FILE"
 echo "Available environments:"
 ls -1 "${SCRIPT_DIR}/../config/parameters-"*.json 2>/dev/null | sed 's/.*parameters-\(.*\)\.json/ - \1/' || echo " (none found)"
 echo ""
 exit 1
fi
# Check for jq
if ! command -v jq &>/dev/null; then
 echo "❌ Error: 'jq' is required but not installed"
 echo "Install with: brew install jq"
 exit 1
fi
log_info "📋 Loading configuration from: $CONFIG_FILE"
# Extract variables from config
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
LOCATION=$(jq -r '.location' "$CONFIG_FILE")
# Validate that environment in config matches parameter
if [ "$ENV" != "$ENVIRONMENT" ]; then
 echo "⚠️ Warning: Environment mismatch"
 echo " Config file environment: $ENV"
 echo " Script parameter: $ENVIRONMENT"
 echo " Using config file environment: $ENV"
 ENVIRONMENT="$ENV"
fi
log_success "✅ Configuration loaded"
echo ""
# ============================================================================
# Azure Authentication
# ============================================================================
source "${SCRIPT_DIR}/helpers/azure-login.sh"
azure_login "$ENVIRONMENT"
# Log to file only (console display already handled by azure_login)
log_auth_details
# Construct resource names (lowercase)
RG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-rg"
VNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-vnet"
SUBNET_CAE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-subnet-cae"
SUBNET_PE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-subnet-pe"
NSG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-nsg"
PRIVATE_DNS_ZONE="privatelink.postgres.database.azure.com"
# Network CIDR blocks (optimized for 200 Container Apps + 30 Private Endpoints)
# VNet: 10.0.0.0/22 = 1,024 IPs (efficient allocation)
# - Container Apps subnet: 10.0.0.0/23 = 512 IPs (supports 200 apps with replicas)
# - Private Endpoints subnet: 10.0.2.0/26 = 64 IPs (supports 30 endpoints)
# - Reserved for future expansion: 10.0.2.64/26, 10.0.2.128/25, 10.0.3.0/24
VNET_CIDR="10.0.0.0/22"
SUBNET_CAE_CIDR="10.0.0.0/23"
SUBNET_PE_CIDR="10.0.2.0/26"
# Tags
TAGS="Environment=${ENVIRONMENT} Project=${PROJECT_NAME} ManagedBy=AzureCLI CreatedDate=$(date +%Y-%m-%d)"
log_info "=========================================="
log_info "Layer 1: Networking Infrastructure"
log_info "=========================================="
log_info "Project: ${PROJECT_NAME}"
log_info "Environment: ${ENVIRONMENT}"
log_info "Location: ${LOCATION}"
log_info "Resource Group: ${RG_NAME}"
log_info "=========================================="
# 1. Create Resource Group (only if it doesn't exist)
echo ""
log_info "📦 Checking Resource Group..."
if az group show --name "$RG_NAME" &>/dev/null; then
 log_success "✅ Resource Group already exists: $RG_NAME"
else
 log_info "📦 Creating Resource Group..."
 log_command "az group create --name $RG_NAME --location $LOCATION --tags $TAGS"
 log_success "✅ Resource Group created: $RG_NAME"
fi
# 2. Create Virtual Network
echo ""
log_info "🌐 Creating Virtual Network..."
log_command "az network vnet create --resource-group $RG_NAME --name $VNET_NAME --location $LOCATION --address-prefixes $VNET_CIDR --tags $TAGS"
log_success "✅ VNet created: $VNET_NAME ($VNET_CIDR)"
# 3. Create Network Security Group
echo ""
log_info "🔒 Creating Network Security Group..."
az network nsg create \
 --resource-group "$RG_NAME" \
 --name "$NSG_NAME" \
 --location "$LOCATION" \
 --tags $TAGS
# Add NSG rules for Container Apps
echo "🔒 Adding NSG rules..."
# Allow HTTPS inbound
az network nsg rule create \
 --resource-group "$RG_NAME" \
 --nsg-name "$NSG_NAME" \
 --name "AllowHttpsInbound" \
 --priority 100 \
 --direction Inbound \
 --access Allow \
 --protocol Tcp \
 --source-address-prefixes Internet \
 --source-port-ranges '*' \
 --destination-address-prefixes '*' \
 --destination-port-ranges 443 \
 --description "Allow HTTPS traffic from Internet"
# Allow VNet internal traffic
az network nsg rule create \
 --resource-group "$RG_NAME" \
 --nsg-name "$NSG_NAME" \
 --name "AllowVnetInbound" \
 --priority 200 \
 --direction Inbound \
 --access Allow \
 --protocol '*' \
 --source-address-prefixes VirtualNetwork \
 --source-port-ranges '*' \
 --destination-address-prefixes VirtualNetwork \
 --destination-port-ranges '*' \
 --description "Allow internal VNet traffic"
# Deny all other inbound
az network nsg rule create \
 --resource-group "$RG_NAME" \
 --nsg-name "$NSG_NAME" \
 --name "DenyAllInbound" \
 --priority 4096 \
 --direction Inbound \
 --access Deny \
 --protocol '*' \
 --source-address-prefixes '*' \
 --source-port-ranges '*' \
 --destination-address-prefixes '*' \
 --destination-port-ranges '*' \
 --description "Deny all other inbound traffic"
log_success "✅ NSG created with security rules: $NSG_NAME"
# 4. Create Subnet for Container Apps Environment
echo ""
echo "🔗 Creating Container Apps Environment Subnet..."
az network vnet subnet create \
 --resource-group "$RG_NAME" \
 --vnet-name "$VNET_NAME" \
 --name "$SUBNET_CAE_NAME" \
 --address-prefixes "$SUBNET_CAE_CIDR" \
 --network-security-group "$NSG_NAME" \
 --delegations "Microsoft.App/environments"
echo "✅ Container Apps subnet created: $SUBNET_CAE_NAME ($SUBNET_CAE_CIDR)"
echo " Delegated to: Microsoft.App/environments"
# 5. Create Subnet for Private Endpoints
echo ""
log_info "🔗 Creating Private Endpoint Subnet..."
az network vnet subnet create \
 --resource-group "$RG_NAME" \
 --vnet-name "$VNET_NAME" \
 --name "$SUBNET_PE_NAME" \
 --address-prefixes "$SUBNET_PE_CIDR" \
 --private-endpoint-network-policies Disabled
log_success "✅ Private Endpoint subnet created: $SUBNET_PE_NAME ($SUBNET_PE_CIDR)"
# 6. Create Private DNS Zone for PostgreSQL
echo ""
log_info "🌐 Creating Private DNS Zone for PostgreSQL..."
az network private-dns zone create \
 --resource-group "$RG_NAME" \
 --name "$PRIVATE_DNS_ZONE" \
 --tags $TAGS
log_success "✅ Private DNS Zone created: $PRIVATE_DNS_ZONE"
# 7. Link Private DNS Zone to VNet
echo ""
log_info "🔗 Linking Private DNS Zone to VNet..."
az network private-dns link vnet create \
 --resource-group "$RG_NAME" \
 --zone-name "$PRIVATE_DNS_ZONE" \
 --name "${VNET_NAME}-link" \
 --virtual-network "$VNET_NAME" \
 --registration-enabled false \
 --tags $TAGS
log_success "✅ Private DNS Zone linked to VNet"
# Summary
echo ""
log_success "=========================================="
log_success "✅ Layer 1 Deployment Complete!"
log_success "=========================================="
log_info "Resources created:"
log_info " - Resource Group: $RG_NAME"
log_info " - VNet: $VNET_NAME ($VNET_CIDR)"
log_info " - Subnet (Container Apps): $SUBNET_CAE_NAME ($SUBNET_CAE_CIDR)"
log_info " - Subnet (Private Endpoints): $SUBNET_PE_NAME ($SUBNET_PE_CIDR)"
log_info " - NSG: $NSG_NAME (with 3 rules)"
log_info " - Private DNS Zone: $PRIVATE_DNS_ZONE"
log_success "=========================================="
echo ""
log_success "Next step: Run ./02-deploy-security.sh ${ENVIRONMENT}"
echo ""
