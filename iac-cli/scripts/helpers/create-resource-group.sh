#!/usr/bin/env bash
#==============================================================================
# Create Azure Resource Group
#==============================================================================
# Purpose: Create a resource group for the platform-nbrly infrastructure
#
# Usage:
# ./scripts/helpers/create-resource-group.sh [environment]
#
# Arguments:
# environment (optional) - Environment name (dev, staging, prod)
# Defaults to "dev"
#
# Example:
# ./scripts/helpers/create-resource-group.sh dev
# ./scripts/helpers/create-resource-group.sh prod
#==============================================================================
set -euo pipefail
# Color codes for output
# Default environment
ENVIRONMENT="${1:-dev}"
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/parameters-${ENVIRONMENT}.json"
echo ""
echo "════════════════════════════════════════════════════════════"
echo " Azure Resource Group Creation"
echo " Environment: ${ENVIRONMENT}"
echo "════════════════════════════════════════════════════════════"
echo ""
#------------------------------------------------------------------------------
# Validate configuration file exists
#------------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
 echo "❌ Configuration file not found: $CONFIG_FILE"
 echo "Available environments:"
 ls -1 "${SCRIPT_DIR}/../../config/parameters-"*.json 2>/dev/null | sed 's/.*parameters-\(.*\)\.json/ - \1/' || echo " (none found)"
 echo ""
 exit 1
fi
#------------------------------------------------------------------------------
# Load configuration
#------------------------------------------------------------------------------
echo "📋 Loading configuration..."
if ! command -v jq &>/dev/null; then
 echo "❌ Error: 'jq' is required but not installed"
 echo "Install with: brew install jq"
 exit 1
fi
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
LOCATION=$(jq -r '.location' "$CONFIG_FILE")
# Construct resource group name
RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"
echo "✅ Configuration loaded"
echo " Project: ${PROJECT_NAME}"
echo " Environment: ${ENV}"
echo " Location: ${LOCATION}"
echo " Resource Group: ${RG_NAME}"
echo ""
#------------------------------------------------------------------------------
# Authenticate to Azure
#------------------------------------------------------------------------------
source "${SCRIPT_DIR}/azure-login.sh"
azure_login "$ENV"
#------------------------------------------------------------------------------
# Check if resource group already exists
#------------------------------------------------------------------------------
echo "🔍 Checking if resource group exists..."
if az group show --name "$RG_NAME" &>/dev/null; then
 echo "⚠️ Resource group already exists: $RG_NAME"
 # Get existing resource group details
 RG_LOCATION=$(az group show --name "$RG_NAME" --query location -o tsv)
 RG_TAGS=$(az group show --name "$RG_NAME" --query tags -o json)
 echo " Existing Details:"
 echo " Location: $RG_LOCATION"
 echo " Tags: $RG_TAGS"
 echo ""
 read -p "Do you want to update the resource group? (y/N): " -n 1 -r
 echo ""
 if [[ ! $REPLY =~ ^[Yy]$ ]]; then
 echo "ℹ️ Skipping resource group creation"
 echo ""
 exit 0
 fi
 ACTION="Updating"
else
 echo "✅ Resource group does not exist, will create new"
 ACTION="Creating"
fi
echo ""
#------------------------------------------------------------------------------
# Create/Update resource group
#------------------------------------------------------------------------------
echo "📦 ${ACTION} resource group..."
# Prepare tags
CREATED_DATE=$(date +%Y-%m-%d)
TAGS="Environment=${ENV} Project=${PROJECT_NAME} ManagedBy=AzureCLI CreatedDate=${CREATED_DATE}"
# Create or update resource group
if az group create \
 --name "$RG_NAME" \
 --location "$LOCATION" \
 --tags $TAGS \
 --output none; then
 ACTION_LOWER=$(echo "$ACTION" | tr '[:upper:]' '[:lower:]')
 echo "✅ Resource group ${ACTION_LOWER} successfully: $RG_NAME"
 echo ""
else
 echo "❌ Failed to create/update resource group"
 exit 1
fi
#------------------------------------------------------------------------------
# Display resource group information
#------------------------------------------------------------------------------
echo "📊 Resource Group Information:"
echo ""
az group show --name "$RG_NAME" --output table
echo ""
echo "🏷️ Tags:"
az group show --name "$RG_NAME" --query tags -o json | jq -r 'to_entries | .[] | " \(.key): \(.value)"'
echo ""
echo "════════════════════════════════════════════════════════════"
echo " ✅ Resource Group Ready"
echo "════════════════════════════════════════════════════════════"
echo ""
#------------------------------------------------------------------------------
# Display resource group ID for use in service principal creation
#------------------------------------------------------------------------------
RG_ID=$(az group show --name "$RG_NAME" --query id -o tsv)
echo "💡 Next Steps:"
echo ""
echo " 1. Create service principal with access to this resource group:"
echo " ./scripts/helpers/create-service-principal.sh $ENV"
echo ""
echo " 2. Or manually create service principal:"
echo " az ad sp create-for-rbac \\"
echo " --name \"sp-${PROJECT_NAME}-${ENV}-deployer\" \\"
echo " --role Contributor \\"
echo " --scopes \"$RG_ID\""
echo ""
echo " 3. Deploy infrastructure:"
echo " cd scripts && ./01-deploy-networking.sh"
echo ""
