#!/usr/bin/env bash
#==============================================================================
# Test Azure Authentication Setup
#==============================================================================
# Purpose: Verify Azure authentication configuration and credential files
#
# Usage:
# ./scripts/test-azure-login.sh [environment]
#
# Arguments:
# environment (optional) - Environment to test (dev, staging, prod)
# Defaults to "dev"
#
# Tests:
# - Credential file existence and format
# - File permissions
# - JSON structure validation
# - Service principal authentication
# - Subscription access
#==============================================================================
set -euo pipefail
# Color codes
# Default environment
ENV="${1:-dev}"
echo ""
echo "════════════════════════════════════════════════════════════"
echo " Azure Authentication Test"
echo " Environment: $ENV"
echo "════════════════════════════════════════════════════════════"
echo ""
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_FILE="$SCRIPT_DIR/../creds/azure-credentials-${ENV}.cred"
#------------------------------------------------------------------------------
# Test 1: Credential file exists
#------------------------------------------------------------------------------
echo "Test 1: Checking credential file existence"
if [[ -f "$CRED_FILE" ]]; then
 echo "✅ Credential file found: $CRED_FILE"
else
 echo "❌ Credential file not found: $CRED_FILE"
 echo "💡 Create it by copying the template:"
 echo " cp creds/azure-credentials.example.json $CRED_FILE"
 echo " vi $CRED_FILE"
 echo ""
 exit 1
fi
echo ""
#------------------------------------------------------------------------------
# Test 2: File permissions
#------------------------------------------------------------------------------
echo "Test 2: Checking file permissions"
if [[ "$OSTYPE" == "darwin"* ]]; then
 PERMS=$(stat -f "%A" "$CRED_FILE")
else
 PERMS=$(stat -c "%a" "$CRED_FILE")
fi
if [[ "$PERMS" == "600" || "$PERMS" == "400" ]]; then
 echo "✅ File permissions are secure: $PERMS"
else
 echo "⚠️ Warning: File permissions are too open: $PERMS"
 echo " Recommended: 600 (owner read-write only)"
 echo " Run: chmod 600 $CRED_FILE"
fi
echo ""
#------------------------------------------------------------------------------
# Test 3: JSON format validation
#------------------------------------------------------------------------------
echo "Test 3: Validating JSON format"
if ! command -v jq &>/dev/null; then
 echo "⚠️ Warning: 'jq' not installed, skipping JSON validation"
 echo " Install with: brew install jq"
else
 if jq empty "$CRED_FILE" 2>/dev/null; then
 echo "✅ JSON syntax is valid"
 # Display credential structure (masked)
 echo " Credential structure:"
 jq -r 'to_entries | .[] | " - \(.key): \(if .key == "clientSecret" then "********" else .value end)"' "$CRED_FILE"
 else
 echo "❌ Invalid JSON syntax"
 exit 1
 fi
fi
echo ""
#------------------------------------------------------------------------------
# Test 4: Required fields
#------------------------------------------------------------------------------
echo "Test 4: Checking required fields"
if command -v jq &>/dev/null; then
 REQUIRED_FIELDS=("subscriptionId" "tenantId" "clientId" "clientSecret" "environment")
 ALL_PRESENT=true
 for field in "${REQUIRED_FIELDS[@]}"; do
 value=$(jq -r ".$field // empty" "$CRED_FILE")
 if [[ -z "$value" || "$value" == "null" ]]; then
 echo "❌ Missing field: $field"
 ALL_PRESENT=false
 elif [[ "$value" == *"your-"* || "$value" == *"xxxx"* ]]; then
 echo "❌ Field '$field' contains placeholder value"
 ALL_PRESENT=false
 else
 echo "✅ Field '$field' is present"
 fi
 done
 if [[ "$ALL_PRESENT" != true ]]; then
 echo ""
 echo "❌ Some required fields are missing or contain placeholders"
 exit 1
 fi
else
 echo "⚠️ Skipping field validation (jq not installed)"
fi
echo ""
#------------------------------------------------------------------------------
# Test 5: Service principal authentication
#------------------------------------------------------------------------------
echo "Test 5: Testing service principal authentication"
# Logout first to ensure clean test
az logout &>/dev/null || true
# Source the authentication helper
source "$SCRIPT_DIR/helpers/azure-login.sh"
# Try to authenticate
if azure_login "$ENV"; then
 echo "✅ Authentication successful"
else
 echo "❌ Authentication failed"
 exit 1
fi
echo ""
#------------------------------------------------------------------------------
# Test 6: Subscription access
#------------------------------------------------------------------------------
echo "Test 6: Verifying subscription access"
if az account show &>/dev/null; then
 SUB_NAME=$(az account show --query name -o tsv)
 SUB_ID=$(az account show --query id -o tsv)
 TENANT_ID=$(az account show --query tenantId -o tsv)
 echo "✅ Successfully connected to Azure"
 echo " Subscription Name: $SUB_NAME"
 echo " Subscription ID: $SUB_ID"
 echo " Tenant ID: $TENANT_ID"
else
 echo "❌ Unable to access subscription"
 exit 1
fi
echo ""
#------------------------------------------------------------------------------
# Test 7: Resource group access (if specified in config)
#------------------------------------------------------------------------------
CONFIG_FILE="$SCRIPT_DIR/../config/parameters-${ENV}.json"
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
 echo "Test 7: Checking resource group access"
 RG_NAME=$(jq -r '.resourceGroup // empty' "$CONFIG_FILE")
 if [[ -n "$RG_NAME" && "$RG_NAME" != "null" ]]; then
 if az group show --name "$RG_NAME" &>/dev/null; then
 echo "✅ Can access resource group: $RG_NAME"
 else
 echo "⚠️ Warning: Cannot access resource group: $RG_NAME"
 echo " The resource group may not exist yet (will be created during deployment)"
 fi
 else
 echo "⚠️ Resource group not specified in config"
 fi
 echo ""
fi
#------------------------------------------------------------------------------
# Test 8: Azure CLI version and extensions
#------------------------------------------------------------------------------
echo "Test 8: Checking Azure CLI environment"
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
echo "✅ Azure CLI version: $AZ_VERSION"
# Check for required extensions
REQUIRED_EXTENSIONS=("containerapp")
for ext in "${REQUIRED_EXTENSIONS[@]}"; do
 if az extension show --name "$ext" &>/dev/null; then
 EXT_VERSION=$(az extension show --name "$ext" --query version -o tsv)
 echo "✅ Extension '$ext' installed: $EXT_VERSION"
 else
 echo "⚠️ Extension '$ext' not installed"
 echo " Install with: az extension add --name $ext"
 fi
done
echo ""
#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo "════════════════════════════════════════════════════════════"
echo " ✅ All tests passed!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Your Azure authentication setup is ready for deployment."
echo ""
echo "Next steps:"
echo " 1. Run infrastructure deployment: ./scripts/01-deploy-networking.sh"
echo " 2. Or run full deployment: for script in scripts/0*.sh; do \$script; done"
echo ""
# Logout after testing
az logout &>/dev/null || true
echo "(Logged out after testing)"
echo ""
