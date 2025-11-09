#!/usr/bin/env bash
#==============================================================================
# Create Azure Resource Group
#==============================================================================
# Purpose: Create a resource group for the platform-nbrly infrastructure
#
# Usage:
#   ./scripts/helpers/create-resource-group.sh [environment]
#
# Arguments:
#   environment (optional) - Environment name (dev, staging, prod)
#                           Defaults to "dev"
#
# Example:
#   ./scripts/helpers/create-resource-group.sh dev
#   ./scripts/helpers/create-resource-group.sh prod
#==============================================================================

set -euo pipefail

# Color codes for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# Default environment
ENVIRONMENT="${1:-dev}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/parameters-${ENVIRONMENT}.json"

echo ""
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Azure Resource Group Creation${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Environment: ${ENVIRONMENT}${COLOR_RESET}"
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

#------------------------------------------------------------------------------
# Validate configuration file exists
#------------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${COLOR_RED}❌ Configuration file not found: $CONFIG_FILE${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Available environments:${COLOR_RESET}"
    ls -1 "${SCRIPT_DIR}/../../config/parameters-"*.json 2>/dev/null | sed 's/.*parameters-\(.*\)\.json/  - \1/' || echo "  (none found)"
    echo ""
    exit 1
fi

#------------------------------------------------------------------------------
# Load configuration
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}📋 Loading configuration...${COLOR_RESET}"

if ! command -v jq &>/dev/null; then
    echo -e "${COLOR_RED}❌ Error: 'jq' is required but not installed${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Install with: brew install jq${COLOR_RESET}"
    exit 1
fi

PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
LOCATION=$(jq -r '.location' "$CONFIG_FILE")

# Construct resource group name
RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"

echo -e "${COLOR_GREEN}✅ Configuration loaded${COLOR_RESET}"
echo -e "   Project: ${PROJECT_NAME}"
echo -e "   Environment: ${ENV}"
echo -e "   Location: ${LOCATION}"
echo -e "   Resource Group: ${RG_NAME}"
echo ""

#------------------------------------------------------------------------------
# Authenticate to Azure
#------------------------------------------------------------------------------
source "${SCRIPT_DIR}/azure-login.sh"
azure_login "$ENV"

#------------------------------------------------------------------------------
# Check if resource group already exists
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}🔍 Checking if resource group exists...${COLOR_RESET}"

if az group show --name "$RG_NAME" &>/dev/null; then
    echo -e "${COLOR_YELLOW}⚠️  Resource group already exists: $RG_NAME${COLOR_RESET}"
    
    # Get existing resource group details
    RG_LOCATION=$(az group show --name "$RG_NAME" --query location -o tsv)
    RG_TAGS=$(az group show --name "$RG_NAME" --query tags -o json)
    
    echo -e "${COLOR_BLUE}   Existing Details:${COLOR_RESET}"
    echo -e "   Location: $RG_LOCATION"
    echo -e "   Tags: $RG_TAGS"
    echo ""
    
    read -p "Do you want to update the resource group? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${COLOR_BLUE}ℹ️  Skipping resource group creation${COLOR_RESET}"
        echo ""
        exit 0
    fi
    
    ACTION="Updating"
else
    echo -e "${COLOR_GREEN}✅ Resource group does not exist, will create new${COLOR_RESET}"
    ACTION="Creating"
fi
echo ""

#------------------------------------------------------------------------------
# Create/Update resource group
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}📦 ${ACTION} resource group...${COLOR_RESET}"

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
    echo -e "${COLOR_GREEN}✅ Resource group ${ACTION_LOWER} successfully: $RG_NAME${COLOR_RESET}"
    echo ""
else
    echo -e "${COLOR_RED}❌ Failed to create/update resource group${COLOR_RESET}"
    exit 1
fi

#------------------------------------------------------------------------------
# Display resource group information
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}📊 Resource Group Information:${COLOR_RESET}"
echo ""

az group show --name "$RG_NAME" --output table

echo ""
echo -e "${COLOR_BLUE}🏷️  Tags:${COLOR_RESET}"
az group show --name "$RG_NAME" --query tags -o json | jq -r 'to_entries | .[] | "   \(.key): \(.value)"'

echo ""
echo -e "${COLOR_GREEN}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_GREEN}  ✅ Resource Group Ready${COLOR_RESET}"
echo -e "${COLOR_GREEN}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

#------------------------------------------------------------------------------
# Display resource group ID for use in service principal creation
#------------------------------------------------------------------------------
RG_ID=$(az group show --name "$RG_NAME" --query id -o tsv)
echo -e "${COLOR_BLUE}💡 Next Steps:${COLOR_RESET}"
echo ""
echo -e "  1. Create service principal with access to this resource group:"
echo -e "     ${COLOR_GREEN}./scripts/helpers/create-service-principal.sh $ENV${COLOR_RESET}"
echo ""
echo -e "  2. Or manually create service principal:"
echo -e "     ${COLOR_GREEN}az ad sp create-for-rbac \\${COLOR_RESET}"
echo -e "       ${COLOR_GREEN}--name \"sp-${PROJECT_NAME}-${ENV}-deployer\" \\${COLOR_RESET}"
echo -e "       ${COLOR_GREEN}--role Contributor \\${COLOR_RESET}"
echo -e "       ${COLOR_GREEN}--scopes \"$RG_ID\"${COLOR_RESET}"
echo ""
echo -e "  3. Deploy infrastructure:"
echo -e "     ${COLOR_GREEN}cd scripts && ./01-deploy-networking.sh${COLOR_RESET}"
echo ""
