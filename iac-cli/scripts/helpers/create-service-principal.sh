#!/usr/bin/env bash
#==============================================================================
# Create Azure Service Principal for Deployment
#==============================================================================
# Purpose: Create a service principal with appropriate permissions for
# deploying and managing platform-nbrly infrastructure
#
# Usage:
# ./scripts/helpers/create-service-principal.sh [environment] [scope] [resource-group]
#
# Arguments:
# environment (optional) - Environment name (dev, staging, prod)
# Defaults to "dev"
# scope (optional) - Permission scope (rg, subscription)
# Defaults to "rg" (resource group)
# resource-group (optional) - Custom resource group name for scope
# Only used when scope is "rg"
# Defaults to derived name from config
#
# Examples:
# # Create SP with resource group scope (recommended)
# ./scripts/helpers/create-service-principal.sh dev
#
# # Create SP with custom resource group scope
# ./scripts/helpers/create-service-principal.sh dev rg my-custom-rg
#
# # Create SP with subscription scope (use with caution)
# ./scripts/helpers/create-service-principal.sh prod subscription
#
# Security Notes:
# - SP credentials are displayed ONCE - save them immediately
# - Credentials are saved to creds/azure-credentials-{env}.cred
# - Use resource group scope for least privilege
# - Rotate credentials every 90 days
#==============================================================================
set -euo pipefail
# Color codes for output
# Default values
ENVIRONMENT="${1:-dev}"
SCOPE="${2:-rg}"
CUSTOM_RG_NAME="${3:-}"
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/parameters-${ENVIRONMENT}.json"
CRED_FILE="${SCRIPT_DIR}/../../creds/azure-credentials-${ENVIRONMENT}.cred"
echo ""
echo "════════════════════════════════════════════════════════════"
echo " Azure Service Principal Creation"
echo " Environment: ${ENVIRONMENT}"
echo " Scope: ${SCOPE}"
echo "════════════════════════════════════════════════════════════"
echo ""
#------------------------------------------------------------------------------
# Validate configuration file exists
#------------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
 echo "❌ Configuration file not found: $CONFIG_FILE"
 echo "💡 Run: ./scripts/helpers/create-resource-group.sh $ENVIRONMENT"
 exit 1
fi
#------------------------------------------------------------------------------
# Check for jq
#------------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
 echo "❌ Error: 'jq' is required but not installed"
 echo "Install with: brew install jq"
 exit 1
fi
#------------------------------------------------------------------------------
# Load configuration
#------------------------------------------------------------------------------
echo "📋 Loading configuration..."
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
# Construct resource names
if [[ -n "$CUSTOM_RG_NAME" ]]; then
 RG_NAME="$CUSTOM_RG_NAME"
 echo "ℹ️ Using custom resource group name: ${RG_NAME}"
else
 RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"
fi
SP_NAME="sp-${PROJECT_NAME}-${ENV}-deployer"
echo "✅ Configuration loaded"
echo " Project: ${PROJECT_NAME}"
echo " Environment: ${ENV}"
echo " Resource Group: ${RG_NAME}"
echo " Service Principal: ${SP_NAME}"
echo ""
#------------------------------------------------------------------------------
# Authenticate to Azure (interactive for SP creation)
#------------------------------------------------------------------------------
echo "🔐 Checking Azure authentication..."
if ! az account show &>/dev/null; then
 echo "Not logged in. Logging in interactively..."
 az login
fi
# Get current subscription details
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "✅ Authenticated to Azure"
echo " Subscription: ${SUBSCRIPTION_NAME}"
echo " Subscription ID: ${SUBSCRIPTION_ID}"
echo " Tenant ID: ${TENANT_ID}"
echo ""
#------------------------------------------------------------------------------
# Determine scope for service principal
#------------------------------------------------------------------------------
echo "🎯 Determining permission scope..."
if [[ "$SCOPE" == "subscription" ]]; then
 SCOPE_PATH="/subscriptions/${SUBSCRIPTION_ID}"
 SCOPE_DISPLAY="Subscription: ${SUBSCRIPTION_NAME}"
 echo "⚠️ WARNING: Creating SP with subscription-wide permissions"
 echo " This grants access to ALL resources in the subscription"
 echo ""
 read -p "Are you sure you want to proceed? (type 'yes' to continue): " CONFIRM
 if [[ "$CONFIRM" != "yes" ]]; then
 echo "ℹ️ Cancelled"
 exit 0
 fi
elif [[ "$SCOPE" == "rg" ]]; then
 # Check if resource group exists
 if ! az group show --name "$RG_NAME" &>/dev/null; then
 echo "❌ Resource group does not exist: $RG_NAME"
 echo "💡 Create it first: ./scripts/helpers/create-resource-group.sh $ENVIRONMENT"
 exit 1
 fi
 SCOPE_PATH=$(az group show --name "$RG_NAME" --query id -o tsv)
 SCOPE_DISPLAY="Resource Group: ${RG_NAME}"
 echo "✅ Using resource group scope (recommended)"
else
 echo "❌ Invalid scope: $SCOPE"
 echo "Valid options: rg, subscription"
 exit 1
fi
echo " Scope: ${SCOPE_DISPLAY}"
echo " Path: ${SCOPE_PATH}"
echo ""
#------------------------------------------------------------------------------
# Check if service principal already exists
#------------------------------------------------------------------------------
echo "🔍 Checking if service principal exists..."
EXISTING_SP=$(az ad sp list --display-name "$SP_NAME" --query "[].appId" -o tsv)
if [[ -n "$EXISTING_SP" ]]; then
 echo "⚠️ Service principal already exists: $SP_NAME"
 echo " App ID: $EXISTING_SP"
 echo ""
 read -p "Do you want to reset credentials (create new secret)? (y/N): " -n 1 -r
 echo ""
 if [[ ! $REPLY =~ ^[Yy]$ ]]; then
 echo "ℹ️ Skipping service principal creation"
 echo ""
 exit 0
 fi
 echo "🔄 Resetting service principal credentials..."
 # Reset credentials (create new secret)
 SP_OUTPUT=$(az ad sp credential reset \
 --id "$EXISTING_SP" \
 --output json)
 ACTION="reset"
else
 echo "✅ Service principal does not exist, will create new"
 echo ""
 #--------------------------------------------------------------------------
 # Create service principal
 #--------------------------------------------------------------------------
 echo "🔧 Creating service principal..."
 SP_OUTPUT=$(az ad sp create-for-rbac \
 --name "$SP_NAME" \
 --role Contributor \
 --scopes "$SCOPE_PATH" \
 --output json)
 ACTION="created"
fi
#------------------------------------------------------------------------------
# Extract service principal details
#------------------------------------------------------------------------------
APP_ID=$(echo "$SP_OUTPUT" | jq -r '.appId')
PASSWORD=$(echo "$SP_OUTPUT" | jq -r '.password')
SP_TENANT_ID=$(echo "$SP_OUTPUT" | jq -r '.tenant')
echo "✅ Service principal ${ACTION} successfully"
echo ""
#------------------------------------------------------------------------------
# Display service principal details
#------------------------------------------------------------------------------
echo "════════════════════════════════════════════════════════════"
echo " ⚠️ SAVE THESE CREDENTIALS IMMEDIATELY ⚠️"
echo " These values will NOT be shown again!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Service Principal Details:"
echo " Name: ${SP_NAME}"
echo " App ID (Client ID): ${APP_ID}"
echo " Password (Secret): ${PASSWORD}"
echo " Tenant ID: ${SP_TENANT_ID}"
echo " Subscription ID: ${SUBSCRIPTION_ID}"
echo " Scope: ${SCOPE_DISPLAY}"
echo ""
#------------------------------------------------------------------------------
# Create credential file
#------------------------------------------------------------------------------
echo "💾 Creating credential file..."
# Ensure creds directory exists
mkdir -p "${SCRIPT_DIR}/../../creds"
# Check if credential file already exists
if [[ -f "$CRED_FILE" ]]; then
 echo "⚠️ Credential file already exists: $CRED_FILE"
 # Backup existing file
 BACKUP_FILE="${CRED_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
 cp "$CRED_FILE" "$BACKUP_FILE"
 echo " Created backup: $BACKUP_FILE"
fi
# Create credential file
cat > "$CRED_FILE" <<EOF
{
 "subscriptionId": "${SUBSCRIPTION_ID}",
 "tenantId": "${SP_TENANT_ID}",
 "clientId": "${APP_ID}",
 "clientSecret": "${PASSWORD}",
 "environment": "${ENV}"
}
EOF
# Set secure permissions
chmod 600 "$CRED_FILE"
echo "✅ Credential file created: $CRED_FILE"
echo " File permissions set to 600 (owner read-write only)"
echo ""
#------------------------------------------------------------------------------
# Verify credential file
#------------------------------------------------------------------------------
echo "✅ Verifying credential file..."
if jq empty "$CRED_FILE" 2>/dev/null; then
 echo "✅ Credential file is valid JSON"
else
 echo "❌ Credential file has invalid JSON format"
 exit 1
fi
echo ""
#------------------------------------------------------------------------------
# Test authentication with new service principal
#------------------------------------------------------------------------------
echo "🧪 Testing service principal authentication..."
# Logout current session
az logout &>/dev/null || true
# Try to login with service principal
if az login --service-principal \
 --username "$APP_ID" \
 --password "$PASSWORD" \
 --tenant "$SP_TENANT_ID" \
 --output none 2>/dev/null; then
 # Set subscription
 az account set --subscription "$SUBSCRIPTION_ID"
 echo "✅ Service principal authentication successful"
 # Display account info
 CURRENT_SUB=$(az account show --query name -o tsv)
 echo " Active subscription: $CURRENT_SUB"
 # Logout after test
 az logout &>/dev/null || true
else
 echo "❌ Service principal authentication failed"
 echo " This might be due to propagation delay. Try again in 1-2 minutes."
fi
echo ""
#------------------------------------------------------------------------------
# Display role assignments
#------------------------------------------------------------------------------
echo "📋 Service Principal Role Assignments:"
echo ""
# Re-login with original account to check roles
az login --output none 2>/dev/null || true
az role assignment list \
 --assignee "$APP_ID" \
 --output table \
 --query "[].{Role:roleDefinitionName, Scope:scope}"
echo ""
#------------------------------------------------------------------------------
# Summary and next steps
#------------------------------------------------------------------------------
echo "════════════════════════════════════════════════════════════"
echo " ✅ Service Principal Setup Complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📝 Summary:"
echo " Service Principal: ${SP_NAME}"
echo " Credential File: ${CRED_FILE}"
echo " Permission Scope: ${SCOPE_DISPLAY}"
echo " Role: Contributor"
echo ""
echo "💡 Next Steps:"
echo ""
echo " 1. Test the authentication setup:"
echo " ./scripts/test-azure-login.sh ${ENV}"
echo ""
echo " 2. Deploy infrastructure:"
echo " cd scripts"
echo " ./01-deploy-networking.sh"
echo ""
echo " 3. (Optional) Create additional service principals for other environments:"
echo " ./scripts/helpers/create-service-principal.sh staging"
echo " ./scripts/helpers/create-service-principal.sh prod"
echo ""
echo "⚠️ Security Reminders:"
echo " - Credential file is gitignored (${CRED_FILE})"
echo " - File permissions are set to 600 (owner-only)"
echo " - DO NOT commit credentials to version control"
echo " - Rotate credentials every 90 days"
echo " - Use least-privilege scopes (resource group preferred)"
echo ""
echo "📖 Documentation:"
echo " - Setup Guide: creds/README.md"
echo " - Authentication Details: docs/azure-authentication-setup.md"
echo ""
