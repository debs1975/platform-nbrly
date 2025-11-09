#!/bin/bash
set -euo pipefail

#==============================================================================
# Script: grant-sp-permissions.sh
# Purpose: Grant necessary RBAC permissions to service principal for deployment
#==============================================================================
# This script grants the service principal the permissions needed to:
# - Create and manage Azure resources
# - Assign RBAC roles to other identities
# - Manage Key Vault access policies
#
# Prerequisites:
# - You must be logged in with an account that has Owner or User Access
#   Administrator role at the subscription or resource group level
# - The service principal must already exist
#
# Usage:
#   ./scripts/helpers/grant-sp-permissions.sh <environment> [scope-level]
#
# Arguments:
#   environment   - Environment name (dev, staging, prod)
#   scope-level   - Optional: 'subscription' or 'resourcegroup' (default: resourcegroup)
#
# Examples:
#   ./scripts/helpers/grant-sp-permissions.sh dev
#   ./scripts/helpers/grant-sp-permissions.sh dev subscription
#   ./scripts/helpers/grant-sp-permissions.sh prod resourcegroup
#==============================================================================

# Color codes
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

# Validate arguments
if [[ $# -lt 1 ]]; then
    echo -e "${COLOR_RED}❌ Error: Missing required argument${COLOR_RESET}"
    echo ""
    echo "Usage: $0 <environment> [scope-level]"
    echo ""
    echo "Arguments:"
    echo "  environment   - Environment name (dev, staging, prod)"
    echo "  scope-level   - Optional: 'subscription' or 'resourcegroup' (default: resourcegroup)"
    echo ""
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 dev subscription"
    echo "  $0 prod resourcegroup"
    exit 1
fi

ENVIRONMENT="$1"
SCOPE_LEVEL="${2:-resourcegroup}"

# Validate scope level
if [[ "$SCOPE_LEVEL" != "subscription" && "$SCOPE_LEVEL" != "resourcegroup" ]]; then
    echo -e "${COLOR_RED}❌ Error: Invalid scope level '$SCOPE_LEVEL'${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   Must be either 'subscription' or 'resourcegroup'${COLOR_RESET}"
    exit 1
fi

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/parameters-${ENVIRONMENT}.json"
CRED_FILE="${SCRIPT_DIR}/../../creds/azure-credentials-${ENVIRONMENT}.cred"

echo ""
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Grant Service Principal Permissions${COLOR_RESET}"
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

# Validate files exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${COLOR_RED}❌ Configuration file not found: $CONFIG_FILE${COLOR_RESET}"
    exit 1
fi

if [[ ! -f "$CRED_FILE" ]]; then
    echo -e "${COLOR_RED}❌ Credential file not found: $CRED_FILE${COLOR_RESET}"
    exit 1
fi

# Check for jq
if ! command -v jq &>/dev/null; then
    echo -e "${COLOR_RED}❌ Error: 'jq' is required but not installed${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Install with: brew install jq${COLOR_RESET}"
    exit 1
fi

# Load configuration
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$CRED_FILE")
SP_CLIENT_ID=$(jq -r '.clientId' "$CRED_FILE")

# Construct resource group name
RG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-rg"

# Get current account info
CURRENT_ACCOUNT=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
if [[ -z "$CURRENT_ACCOUNT" ]]; then
    echo -e "${COLOR_RED}❌ Not logged in to Azure${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   Please run: az login${COLOR_RESET}"
    exit 1
fi

echo -e "${COLOR_BLUE}Configuration:${COLOR_RESET}"
echo -e "  Environment: ${COLOR_CYAN}${ENVIRONMENT}${COLOR_RESET}"
echo -e "  Project: ${COLOR_CYAN}${PROJECT_NAME}${COLOR_RESET}"
echo -e "  Subscription ID: ${COLOR_YELLOW}${SUBSCRIPTION_ID}${COLOR_RESET}"
echo -e "  Service Principal: ${COLOR_YELLOW}${SP_CLIENT_ID}${COLOR_RESET}"
echo -e "  Current Account: ${COLOR_CYAN}${CURRENT_ACCOUNT}${COLOR_RESET}"
echo -e "  Scope Level: ${COLOR_CYAN}${SCOPE_LEVEL}${COLOR_RESET}"
echo ""

# Determine scope
if [[ "$SCOPE_LEVEL" == "subscription" ]]; then
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
    SCOPE_NAME="Subscription"
else
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}"
    SCOPE_NAME="Resource Group (${RG_NAME})"
fi

echo -e "${COLOR_BLUE}Permissions will be granted at: ${COLOR_CYAN}${SCOPE_NAME}${COLOR_RESET}"
echo ""

# Confirm
echo -e "${COLOR_YELLOW}⚠️  This will grant the following roles to the service principal:${COLOR_RESET}"
echo -e "   1. ${COLOR_CYAN}Contributor${COLOR_RESET} - Create and manage resources"
echo -e "   2. ${COLOR_CYAN}User Access Administrator${COLOR_RESET} - Assign RBAC roles"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${COLOR_YELLOW}Cancelled${COLOR_RESET}"
    exit 0
fi

echo ""
echo -e "${COLOR_BLUE}🔒 Granting permissions...${COLOR_RESET}"
echo ""

# 1. Grant Contributor role
echo -e "${COLOR_BLUE}1. Granting Contributor role...${COLOR_RESET}"
if az role assignment create \
    --assignee "$SP_CLIENT_ID" \
    --role "Contributor" \
    --scope "$SCOPE" \
    --output none 2>/dev/null; then
    echo -e "${COLOR_GREEN}   ✅ Contributor role granted${COLOR_RESET}"
else
    # Check if already assigned
    if az role assignment list \
        --assignee "$SP_CLIENT_ID" \
        --role "Contributor" \
        --scope "$SCOPE" \
        --query "[].roleDefinitionName" -o tsv 2>/dev/null | grep -q "Contributor"; then
        echo -e "${COLOR_YELLOW}   ℹ️  Contributor role already assigned${COLOR_RESET}"
    else
        echo -e "${COLOR_RED}   ❌ Failed to grant Contributor role${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}   You may not have sufficient permissions${COLOR_RESET}"
        exit 1
    fi
fi

# 2. Grant User Access Administrator role
echo -e "${COLOR_BLUE}2. Granting User Access Administrator role...${COLOR_RESET}"
if az role assignment create \
    --assignee "$SP_CLIENT_ID" \
    --role "User Access Administrator" \
    --scope "$SCOPE" \
    --output none 2>/dev/null; then
    echo -e "${COLOR_GREEN}   ✅ User Access Administrator role granted${COLOR_RESET}"
else
    # Check if already assigned
    if az role assignment list \
        --assignee "$SP_CLIENT_ID" \
        --role "User Access Administrator" \
        --scope "$SCOPE" \
        --query "[].roleDefinitionName" -o tsv 2>/dev/null | grep -q "User Access Administrator"; then
        echo -e "${COLOR_YELLOW}   ℹ️  User Access Administrator role already assigned${COLOR_RESET}"
    else
        echo -e "${COLOR_RED}   ❌ Failed to grant User Access Administrator role${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}   You may not have sufficient permissions${COLOR_RESET}"
        exit 1
    fi
fi

# Summary
echo ""
echo -e "${COLOR_GREEN}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_GREEN}✅ Service Principal Permissions Granted Successfully${COLOR_RESET}"
echo -e "${COLOR_GREEN}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo -e "${COLOR_BLUE}Service Principal:${COLOR_RESET} ${COLOR_YELLOW}${SP_CLIENT_ID}${COLOR_RESET}"
echo -e "${COLOR_BLUE}Scope:${COLOR_RESET} ${COLOR_CYAN}${SCOPE_NAME}${COLOR_RESET}"
echo ""
echo -e "${COLOR_BLUE}Roles Assigned:${COLOR_RESET}"
echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} Contributor"
echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} User Access Administrator"
echo ""
echo -e "${COLOR_GREEN}The service principal can now:${COLOR_RESET}"
echo -e "  • Create and manage Azure resources"
echo -e "  • Assign RBAC roles to other identities"
echo -e "  • Deploy infrastructure using the deployment scripts"
echo ""
echo -e "${COLOR_CYAN}Next step:${COLOR_RESET} Run your deployment script again"
echo -e "  ${COLOR_YELLOW}./scripts/02-deploy-security.sh ${ENVIRONMENT}${COLOR_RESET}"
echo ""
