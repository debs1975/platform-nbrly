#!/usr/bin/env bash
#==============================================================================
# Create Azure Service Principal for Deployment
#==============================================================================
# Purpose: Create a service principal with appropriate permissions for
#          deploying and managing platform-nbrly infrastructure
#
# Usage:
#   ./scripts/helpers/create-service-principal.sh [environment] [scope] [resource-group]
#
# Arguments:
#   environment (optional)     - Environment name (dev, staging, prod)
#                                Defaults to "dev"
#   scope (optional)          - Permission scope (rg, subscription)
#                                Defaults to "rg" (resource group)
#   resource-group (optional) - Custom resource group name for scope
#                                Only used when scope is "rg"
#                                Defaults to derived name from config
#
# Examples:
#   # Create SP with resource group scope (recommended)
#   ./scripts/helpers/create-service-principal.sh dev
#
#   # Create SP with custom resource group scope
#   ./scripts/helpers/create-service-principal.sh dev rg my-custom-rg
#
#   # Create SP with subscription scope (use with caution)
#   ./scripts/helpers/create-service-principal.sh prod subscription
#
# Security Notes:
#   - SP credentials are displayed ONCE - save them immediately
#   - Credentials are saved to creds/azure-credentials-{env}.cred
#   - Use resource group scope for least privilege
#   - Rotate credentials every 90 days
#==============================================================================

set -euo pipefail

# Color codes for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

# Default values
ENVIRONMENT="${1:-dev}"
SCOPE="${2:-rg}"
CUSTOM_RG_NAME="${3:-}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/parameters-${ENVIRONMENT}.json"
CRED_FILE="${SCRIPT_DIR}/../../creds/azure-credentials-${ENVIRONMENT}.cred"

echo ""
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Azure Service Principal Creation${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Environment: ${ENVIRONMENT}${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Scope: ${SCOPE}${COLOR_RESET}"
echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

#------------------------------------------------------------------------------
# Validate configuration file exists
#------------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${COLOR_RED}❌ Configuration file not found: $CONFIG_FILE${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}💡 Run: ./scripts/helpers/create-resource-group.sh $ENVIRONMENT${COLOR_RESET}"
    exit 1
fi

#------------------------------------------------------------------------------
# Check for jq
#------------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
    echo -e "${COLOR_RED}❌ Error: 'jq' is required but not installed${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Install with: brew install jq${COLOR_RESET}"
    exit 1
fi

#------------------------------------------------------------------------------
# Load configuration
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}📋 Loading configuration...${COLOR_RESET}"

PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")

# Construct resource names
if [[ -n "$CUSTOM_RG_NAME" ]]; then
    RG_NAME="$CUSTOM_RG_NAME"
    echo -e "${COLOR_CYAN}ℹ️  Using custom resource group name: ${RG_NAME}${COLOR_RESET}"
else
    RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"
fi

SP_NAME="sp-${PROJECT_NAME}-${ENV}-deployer"

echo -e "${COLOR_GREEN}✅ Configuration loaded${COLOR_RESET}"
echo -e "   Project: ${PROJECT_NAME}"
echo -e "   Environment: ${ENV}"
echo -e "   Resource Group: ${RG_NAME}"
echo -e "   Service Principal: ${SP_NAME}"
echo ""

#------------------------------------------------------------------------------
# Authenticate to Azure (interactive for SP creation)
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}🔐 Checking Azure authentication...${COLOR_RESET}"

if ! az account show &>/dev/null; then
    echo -e "${COLOR_YELLOW}Not logged in. Logging in interactively...${COLOR_RESET}"
    az login
fi

# Get current subscription details
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo -e "${COLOR_GREEN}✅ Authenticated to Azure${COLOR_RESET}"
echo -e "   Subscription: ${SUBSCRIPTION_NAME}"
echo -e "   Subscription ID: ${SUBSCRIPTION_ID}"
echo -e "   Tenant ID: ${TENANT_ID}"
echo ""

#------------------------------------------------------------------------------
# Determine scope for service principal
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}🎯 Determining permission scope...${COLOR_RESET}"

if [[ "$SCOPE" == "subscription" ]]; then
    SCOPE_PATH="/subscriptions/${SUBSCRIPTION_ID}"
    SCOPE_DISPLAY="Subscription: ${SUBSCRIPTION_NAME}"
    
    echo -e "${COLOR_YELLOW}⚠️  WARNING: Creating SP with subscription-wide permissions${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   This grants access to ALL resources in the subscription${COLOR_RESET}"
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to continue): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        echo -e "${COLOR_BLUE}ℹ️  Cancelled${COLOR_RESET}"
        exit 0
    fi
    
elif [[ "$SCOPE" == "rg" ]]; then
    # Check if resource group exists
    if ! az group show --name "$RG_NAME" &>/dev/null; then
        echo -e "${COLOR_RED}❌ Resource group does not exist: $RG_NAME${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}💡 Create it first: ./scripts/helpers/create-resource-group.sh $ENVIRONMENT${COLOR_RESET}"
        exit 1
    fi
    
    SCOPE_PATH=$(az group show --name "$RG_NAME" --query id -o tsv)
    SCOPE_DISPLAY="Resource Group: ${RG_NAME}"
    
    echo -e "${COLOR_GREEN}✅ Using resource group scope (recommended)${COLOR_RESET}"
    
else
    echo -e "${COLOR_RED}❌ Invalid scope: $SCOPE${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Valid options: rg, subscription${COLOR_RESET}"
    exit 1
fi

echo -e "   Scope: ${SCOPE_DISPLAY}"
echo -e "   Path: ${SCOPE_PATH}"
echo ""

#------------------------------------------------------------------------------
# Check if service principal already exists
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}🔍 Checking if service principal exists...${COLOR_RESET}"

EXISTING_SP=$(az ad sp list --display-name "$SP_NAME" --query "[].appId" -o tsv)

if [[ -n "$EXISTING_SP" ]]; then
    echo -e "${COLOR_YELLOW}⚠️  Service principal already exists: $SP_NAME${COLOR_RESET}"
    echo -e "   App ID: $EXISTING_SP"
    echo ""
    
    read -p "Do you want to reset credentials (create new secret)? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${COLOR_BLUE}ℹ️  Skipping service principal creation${COLOR_RESET}"
        echo ""
        exit 0
    fi
    
    echo -e "${COLOR_BLUE}🔄 Resetting service principal credentials...${COLOR_RESET}"
    
    # Reset credentials (create new secret)
    SP_OUTPUT=$(az ad sp credential reset \
        --id "$EXISTING_SP" \
        --output json)
    
    ACTION="reset"
else
    echo -e "${COLOR_GREEN}✅ Service principal does not exist, will create new${COLOR_RESET}"
    echo ""
    
    #--------------------------------------------------------------------------
    # Create service principal
    #--------------------------------------------------------------------------
    echo -e "${COLOR_BLUE}🔧 Creating service principal...${COLOR_RESET}"
    
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

echo -e "${COLOR_GREEN}✅ Service principal ${ACTION} successfully${COLOR_RESET}"
echo ""

#------------------------------------------------------------------------------
# Display service principal details
#------------------------------------------------------------------------------
echo -e "${COLOR_CYAN}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_CYAN}  ⚠️  SAVE THESE CREDENTIALS IMMEDIATELY ⚠️${COLOR_RESET}"
echo -e "${COLOR_CYAN}  These values will NOT be shown again!${COLOR_RESET}"
echo -e "${COLOR_CYAN}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo -e "${COLOR_YELLOW}Service Principal Details:${COLOR_RESET}"
echo -e "  Name:           ${SP_NAME}"
echo -e "  App ID (Client ID):  ${APP_ID}"
echo -e "  Password (Secret):   ${PASSWORD}"
echo -e "  Tenant ID:           ${SP_TENANT_ID}"
echo -e "  Subscription ID:     ${SUBSCRIPTION_ID}"
echo -e "  Scope:               ${SCOPE_DISPLAY}"
echo ""

#------------------------------------------------------------------------------
# Create credential file
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}💾 Creating credential file...${COLOR_RESET}"

# Ensure creds directory exists
mkdir -p "${SCRIPT_DIR}/../../creds"

# Check if credential file already exists
if [[ -f "$CRED_FILE" ]]; then
    echo -e "${COLOR_YELLOW}⚠️  Credential file already exists: $CRED_FILE${COLOR_RESET}"
    
    # Backup existing file
    BACKUP_FILE="${CRED_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$CRED_FILE" "$BACKUP_FILE"
    echo -e "${COLOR_YELLOW}   Created backup: $BACKUP_FILE${COLOR_RESET}"
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

echo -e "${COLOR_GREEN}✅ Credential file created: $CRED_FILE${COLOR_RESET}"
echo -e "   File permissions set to 600 (owner read-write only)"
echo ""

#------------------------------------------------------------------------------
# Verify credential file
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}✅ Verifying credential file...${COLOR_RESET}"

if jq empty "$CRED_FILE" 2>/dev/null; then
    echo -e "${COLOR_GREEN}✅ Credential file is valid JSON${COLOR_RESET}"
else
    echo -e "${COLOR_RED}❌ Credential file has invalid JSON format${COLOR_RESET}"
    exit 1
fi
echo ""

#------------------------------------------------------------------------------
# Test authentication with new service principal
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}🧪 Testing service principal authentication...${COLOR_RESET}"

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
    
    echo -e "${COLOR_GREEN}✅ Service principal authentication successful${COLOR_RESET}"
    
    # Display account info
    CURRENT_SUB=$(az account show --query name -o tsv)
    echo -e "   Active subscription: $CURRENT_SUB"
    
    # Logout after test
    az logout &>/dev/null || true
else
    echo -e "${COLOR_RED}❌ Service principal authentication failed${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   This might be due to propagation delay. Try again in 1-2 minutes.${COLOR_RESET}"
fi
echo ""

#------------------------------------------------------------------------------
# Display role assignments
#------------------------------------------------------------------------------
echo -e "${COLOR_BLUE}📋 Service Principal Role Assignments:${COLOR_RESET}"
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
echo -e "${COLOR_GREEN}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_GREEN}  ✅ Service Principal Setup Complete${COLOR_RESET}"
echo -e "${COLOR_GREEN}════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

echo -e "${COLOR_BLUE}📝 Summary:${COLOR_RESET}"
echo -e "  Service Principal: ${SP_NAME}"
echo -e "  Credential File: ${CRED_FILE}"
echo -e "  Permission Scope: ${SCOPE_DISPLAY}"
echo -e "  Role: Contributor"
echo ""

echo -e "${COLOR_BLUE}💡 Next Steps:${COLOR_RESET}"
echo ""
echo -e "  1. Test the authentication setup:"
echo -e "     ${COLOR_GREEN}./scripts/test-azure-login.sh ${ENV}${COLOR_RESET}"
echo ""
echo -e "  2. Deploy infrastructure:"
echo -e "     ${COLOR_GREEN}cd scripts${COLOR_RESET}"
echo -e "     ${COLOR_GREEN}./01-deploy-networking.sh${COLOR_RESET}"
echo ""
echo -e "  3. (Optional) Create additional service principals for other environments:"
echo -e "     ${COLOR_GREEN}./scripts/helpers/create-service-principal.sh staging${COLOR_RESET}"
echo -e "     ${COLOR_GREEN}./scripts/helpers/create-service-principal.sh prod${COLOR_RESET}"
echo ""

echo -e "${COLOR_YELLOW}⚠️  Security Reminders:${COLOR_RESET}"
echo -e "  - Credential file is gitignored (${CRED_FILE})"
echo -e "  - File permissions are set to 600 (owner-only)"
echo -e "  - DO NOT commit credentials to version control"
echo -e "  - Rotate credentials every 90 days"
echo -e "  - Use least-privilege scopes (resource group preferred)"
echo ""

echo -e "${COLOR_CYAN}📖 Documentation:${COLOR_RESET}"
echo -e "  - Setup Guide: creds/README.md"
echo -e "  - Authentication Details: docs/azure-authentication-setup.md"
echo ""
