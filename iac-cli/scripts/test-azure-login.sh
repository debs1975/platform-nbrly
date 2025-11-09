#!/usr/bin/env bash
#==============================================================================
# Test Azure Authentication Setup
#==============================================================================
# Purpose: Verify Azure authentication configuration and credential files
#
# Usage:
#   ./scripts/test-azure-login.sh [environment]
#
# Arguments:
#   environment (optional) - Environment to test (dev, staging, prod)
#                           Defaults to "dev"
#
# Tests:
#   - Credential file existence and format
#   - File permissions
#   - JSON structure validation
#   - Service principal authentication
#   - Subscription access
#==============================================================================

set -euo pipefail

# Color codes
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# Default environment
ENV="${1:-dev}"

echo ""
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Azure Authentication Test${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Environment: $ENV${COLOR_RESET}"
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_FILE="$SCRIPT_DIR/../creds/azure-credentials-${ENV}.cred"

#------------------------------------------------------------------------------
# Test 1: Credential file exists
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}Test 1: Checking credential file existence${COLOR_RESET}"
if [[ -f "$CRED_FILE" ]]; then
    echo -e "${COLOR_GREEN}✅ Credential file found: $CRED_FILE${COLOR_RESET}"
else
    echo -e "${COLOR_RED}❌ Credential file not found: $CRED_FILE${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}💡 Create it by copying the template:${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   cp creds/azure-credentials.example.json $CRED_FILE${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   vi $CRED_FILE${COLOR_RESET}"
    echo ""
    exit 1
fi
echo ""

#------------------------------------------------------------------------------
# Test 2: File permissions
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}Test 2: Checking file permissions${COLOR_RESET}"
if [[ "$OSTYPE" == "darwin"* ]]; then
    PERMS=$(stat -f "%A" "$CRED_FILE")
else
    PERMS=$(stat -c "%a" "$CRED_FILE")
fi

if [[ "$PERMS" == "600" || "$PERMS" == "400" ]]; then
    echo -e "${COLOR_GREEN}✅ File permissions are secure: $PERMS${COLOR_RESET}"
else
    echo -e "${COLOR_YELLOW}⚠️  Warning: File permissions are too open: $PERMS${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   Recommended: 600 (owner read-write only)${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   Run: chmod 600 $CRED_FILE${COLOR_RESET}"
fi
echo ""

#------------------------------------------------------------------------------
# Test 3: JSON format validation
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}Test 3: Validating JSON format${COLOR_RESET}"
if ! command -v jq &>/dev/null; then
    echo -e "${COLOR_YELLOW}⚠️  Warning: 'jq' not installed, skipping JSON validation${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   Install with: brew install jq${COLOR_RESET}"
else
    if jq empty "$CRED_FILE" 2>/dev/null; then
        echo -e "${COLOR_GREEN}✅ JSON syntax is valid${COLOR_RESET}"
        
        # Display credential structure (masked)
        echo -e "${COLOR_BLUE}   Credential structure:${COLOR_RESET}"
        jq -r 'to_entries | .[] | "   - \(.key): \(if .key == "clientSecret" then "********" else .value end)"' "$CRED_FILE"
    else
        echo -e "${COLOR_RED}❌ Invalid JSON syntax${COLOR_RESET}"
        exit 1
    fi
fi
echo ""

#------------------------------------------------------------------------------
# Test 4: Required fields
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}Test 4: Checking required fields${COLOR_RESET}"
if command -v jq &>/dev/null; then
    REQUIRED_FIELDS=("subscriptionId" "tenantId" "clientId" "clientSecret" "environment")
    ALL_PRESENT=true
    
    for field in "${REQUIRED_FIELDS[@]}"; do
        value=$(jq -r ".$field // empty" "$CRED_FILE")
        if [[ -z "$value" || "$value" == "null" ]]; then
            echo -e "${COLOR_RED}❌ Missing field: $field${COLOR_RESET}"
            ALL_PRESENT=false
        elif [[ "$value" == *"your-"* || "$value" == *"xxxx"* ]]; then
            echo -e "${COLOR_RED}❌ Field '$field' contains placeholder value${COLOR_RESET}"
            ALL_PRESENT=false
        else
            echo -e "${COLOR_GREEN}✅ Field '$field' is present${COLOR_RESET}"
        fi
    done
    
    if [[ "$ALL_PRESENT" != true ]]; then
        echo ""
        echo -e "${COLOR_RED}❌ Some required fields are missing or contain placeholders${COLOR_RESET}"
        exit 1
    fi
else
    echo -e "${COLOR_YELLOW}⚠️  Skipping field validation (jq not installed)${COLOR_RESET}"
fi
echo ""

#------------------------------------------------------------------------------
# Test 5: Service principal authentication
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}Test 5: Testing service principal authentication${COLOR_RESET}"

# Logout first to ensure clean test
az logout &>/dev/null || true

# Source the authentication helper
source "$SCRIPT_DIR/helpers/azure-login.sh"

# Try to authenticate
if azure_login "$ENV"; then
    echo -e "${COLOR_GREEN}✅ Authentication successful${COLOR_RESET}"
else
    echo -e "${COLOR_RED}❌ Authentication failed${COLOR_RESET}"
    exit 1
fi
echo ""

#------------------------------------------------------------------------------
# Test 6: Subscription access
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}Test 6: Verifying subscription access${COLOR_RESET}"
if az account show &>/dev/null; then
    SUB_NAME=$(az account show --query name -o tsv)
    SUB_ID=$(az account show --query id -o tsv)
    TENANT_ID=$(az account show --query tenantId -o tsv)
    
    echo -e "${COLOR_GREEN}✅ Successfully connected to Azure${COLOR_RESET}"
    echo -e "${COLOR_GREEN}   Subscription Name: $SUB_NAME${COLOR_RESET}"
    echo -e "${COLOR_GREEN}   Subscription ID: $SUB_ID${COLOR_RESET}"
    echo -e "${COLOR_GREEN}   Tenant ID: $TENANT_ID${COLOR_RESET}"
else
    echo -e "${COLOR_RED}❌ Unable to access subscription${COLOR_RESET}"
    exit 1
fi
echo ""

#------------------------------------------------------------------------------
# Test 7: Resource group access (if specified in config)
#------------------------------------------------------------------------------
CONFIG_FILE="$SCRIPT_DIR/../config/parameters-${ENV}.json"
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
    echo -e "${COLOR_BLUE}Test 7: Checking resource group access${COLOR_RESET}"
    RG_NAME=$(jq -r '.resourceGroup // empty' "$CONFIG_FILE")
    
    if [[ -n "$RG_NAME" && "$RG_NAME" != "null" ]]; then
        if az group show --name "$RG_NAME" &>/dev/null; then
            echo -e "${COLOR_GREEN}✅ Can access resource group: $RG_NAME${COLOR_RESET}"
        else
            echo -e "${COLOR_YELLOW}⚠️  Warning: Cannot access resource group: $RG_NAME${COLOR_RESET}"
            echo -e "${COLOR_YELLOW}   The resource group may not exist yet (will be created during deployment)${COLOR_RESET}"
        fi
    else
        echo -e "${COLOR_YELLOW}⚠️  Resource group not specified in config${COLOR_RESET}"
    fi
    echo ""
fi

#------------------------------------------------------------------------------
# Test 8: Azure CLI version and extensions
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}Test 8: Checking Azure CLI environment${COLOR_RESET}"
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
echo -e "${COLOR_GREEN}✅ Azure CLI version: $AZ_VERSION${COLOR_RESET}"

# Check for required extensions
REQUIRED_EXTENSIONS=("containerapp")
for ext in "${REQUIRED_EXTENSIONS[@]}"; do
    if az extension show --name "$ext" &>/dev/null; then
        EXT_VERSION=$(az extension show --name "$ext" --query version -o tsv)
        echo -e "${COLOR_GREEN}✅ Extension '$ext' installed: $EXT_VERSION${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}⚠️  Extension '$ext' not installed${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}   Install with: az extension add --name $ext${COLOR_RESET}"
    fi
done
echo ""

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_GREEN}  ✅ All tests passed!${COLOR_RESET}"
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo -e "${COLOR_GREEN}Your Azure authentication setup is ready for deployment.${COLOR_RESET}"
echo ""
echo -e "${COLOR_BLUE}Next steps:${COLOR_RESET}"
echo -e "  1. Run infrastructure deployment: ${COLOR_GREEN}./scripts/01-deploy-networking.sh${COLOR_RESET}"
echo -e "  2. Or run full deployment: ${COLOR_GREEN}for script in scripts/0*.sh; do \$script; done${COLOR_RESET}"
echo ""

# Logout after testing
az logout &>/dev/null || true
echo -e "${COLOR_BLUE}(Logged out after testing)${COLOR_RESET}"
echo ""
