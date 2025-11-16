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
# Administrator role at the subscription or resource group level
# - The service principal must already exist
#
# Usage:
# ./scripts/helpers/grant-sp-permissions.sh <environment> [scope-level] [role1] [role2] ...
#
# Arguments:
# environment - Environment name (dev, staging, prod)
# scope-level - Optional: 'subscription' or 'resourcegroup' (default: resourcegroup)
# roles       - Optional: Custom roles to assign (default: Contributor and User Access Administrator)
#
# Examples:
# ./scripts/helpers/grant-sp-permissions.sh dev
# ./scripts/helpers/grant-sp-permissions.sh dev subscription
# ./scripts/helpers/grant-sp-permissions.sh prod resourcegroup Owner
# ./scripts/helpers/grant-sp-permissions.sh dev subscription "Contributor" "Key Vault Administrator"
#==============================================================================

# Validate arguments
if [[ $# -lt 1 ]]; then
 echo "❌ Error: Missing required argument"
 echo ""
 echo "Usage: $0 <environment> [scope-level] [role1] [role2] ..."
 echo ""
 echo "Arguments:"
 echo " environment - Environment name (dev, staging, prod)"
 echo " scope-level - Optional: 'subscription' or 'resourcegroup' (default: resourcegroup)"
 echo " roles       - Optional: Custom roles to assign (default: Contributor and User Access Administrator)"
 echo ""
 echo "Examples:"
 echo " $0 dev"
 echo " $0 dev subscription"
 echo " $0 prod resourcegroup Owner"
 echo " $0 dev subscription \"Contributor\" \"Key Vault Administrator\""
 exit 1
fi

ENVIRONMENT="$1"
SCOPE_LEVEL="${2:-resourcegroup}"

# Parse roles - if none provided, use defaults
ROLES=()
if [[ $# -gt 2 ]]; then
    # Custom roles provided
    for ((i=3; i<=$#; i++)); do
        ROLES+=("${!i}")
    done
else
    # Default roles
    ROLES=("Contributor" "User Access Administrator")
fi

# Validate scope level
if [[ "$SCOPE_LEVEL" != "subscription" && "$SCOPE_LEVEL" != "resourcegroup" ]]; then
 echo "❌ Error: Invalid scope level '$SCOPE_LEVEL'"
 echo " Must be either 'subscription' or 'resourcegroup'"
 exit 1
fi

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/parameters-${ENVIRONMENT}.json"
CRED_FILE="${SCRIPT_DIR}/../../creds/azure-credentials-${ENVIRONMENT}.cred"

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Grant Service Principal Permissions"
echo "════════════════════════════════════════════════════════════"
echo ""

# Validate files exist
if [[ ! -f "$CONFIG_FILE" ]]; then
 echo "❌ Configuration file not found: $CONFIG_FILE"
 exit 1
fi

if [[ ! -f "$CRED_FILE" ]]; then
 echo "❌ Credential file not found: $CRED_FILE"
 exit 1
fi

# Check for jq
if ! command -v jq &>/dev/null; then
 echo "❌ Error: 'jq' is required but not installed"
 echo "Install with: brew install jq"
 exit 1
fi

# Load configuration
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$CRED_FILE")
SP_CLIENT_ID=$(jq -r '.clientId' "$CRED_FILE")

# Get service principal details
echo "🔍 Retrieving service principal details..."
SP_DISPLAY_NAME=$(az ad sp show --id "$SP_CLIENT_ID" --query displayName -o tsv 2>/dev/null || echo "N/A")
SP_OBJECT_ID=$(az ad sp show --id "$SP_CLIENT_ID" --query id -o tsv 2>/dev/null || echo "N/A")

if [[ "$SP_DISPLAY_NAME" == "N/A" ]]; then
    echo "⚠️  Warning: Could not retrieve service principal details"
    echo "   This may indicate the service principal doesn't exist or you lack permissions"
    echo ""
fi

# Construct resource group name
RG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-rg"

# Get current account info
CURRENT_ACCOUNT=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
if [[ -z "$CURRENT_ACCOUNT" ]]; then
 echo "❌ Not logged in to Azure"
 echo " Please run: az login"
 exit 1
fi

echo "Configuration:"
echo " Environment: ${ENVIRONMENT}"
echo " Project: ${PROJECT_NAME}"
echo " Subscription ID: ${SUBSCRIPTION_ID}"
echo " Service Principal:"
echo "   - Display Name: ${SP_DISPLAY_NAME}"
echo "   - Client ID (App ID): ${SP_CLIENT_ID}"
echo "   - Object ID: ${SP_OBJECT_ID}"
echo " Current Account: ${CURRENT_ACCOUNT}"
echo " Scope Level: ${SCOPE_LEVEL}"
echo " Roles to assign: ${ROLES[*]}"
echo ""

# Determine scope
if [[ "$SCOPE_LEVEL" == "subscription" ]]; then
 SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
 SCOPE_NAME="Subscription"
else
 SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}"
 SCOPE_NAME="Resource Group (${RG_NAME})"
fi

echo "Permissions will be granted at: ${SCOPE_NAME}"
echo ""

# Confirm
echo "⚠️ This will grant the following roles to the service principal:"
for i in "${!ROLES[@]}"; do
    echo " $((i+1)). ${ROLES[i]}"
done
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
 echo "Cancelled"
 exit 0
fi

echo ""
echo "🔒 Granting permissions..."
echo ""

# Grant each role
ASSIGNED_ROLES=()
for i in "${!ROLES[@]}"; do
    ROLE="${ROLES[i]}"
    echo "$((i+1)). Granting ${ROLE} role..."
    
    if az role assignment create \
     --assignee "$SP_CLIENT_ID" \
     --role "$ROLE" \
     --scope "$SCOPE" \
     --output none 2>/dev/null; then
     echo " ✅ ${ROLE} role granted"
     ASSIGNED_ROLES+=("$ROLE")
    else
     # Check if already assigned
     if az role assignment list \
     --assignee "$SP_CLIENT_ID" \
     --role "$ROLE" \
     --scope "$SCOPE" \
     --query "[].roleDefinitionName" -o tsv 2>/dev/null | grep -q "$ROLE"; then
     echo " ℹ️ ${ROLE} role already assigned"
     ASSIGNED_ROLES+=("$ROLE")
     else
     echo " ❌ Failed to grant ${ROLE} role"
     echo " You may not have sufficient permissions or the role name is invalid"
     echo " Valid role names include: Contributor, Owner, Reader, User Access Administrator, etc."
     exit 1
     fi
    fi
done

# Summary
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ Service Principal Permissions Granted Successfully"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Service Principal:"
echo " - Name: ${SP_DISPLAY_NAME}"
echo " - Client ID: ${SP_CLIENT_ID}"
echo " - Object ID: ${SP_OBJECT_ID}"
echo ""
echo "Scope: ${SCOPE_NAME}"
echo ""
echo "Roles Assigned:"
for role in "${ASSIGNED_ROLES[@]}"; do
    echo " ✓ $role"
done
echo ""

# Provide role-specific capabilities
echo "The service principal can now:"
for role in "${ASSIGNED_ROLES[@]}"; do
    case "$role" in
        "Owner")
            echo " • Full access to all resources and can assign roles to others"
            ;;
        "Contributor")
            echo " • Create and manage Azure resources"
            ;;
        "User Access Administrator")
            echo " • Assign RBAC roles to other identities"
            ;;
        "Key Vault Administrator")
            echo " • Manage Key Vault access policies and secrets"
            ;;
        "Reader")
            echo " • View existing Azure resources"
            ;;
        *)
            echo " • Perform actions allowed by the $role role"
            ;;
    esac
done
echo " • Deploy infrastructure using the deployment scripts"
echo ""
echo "Next step: Run your deployment script again"
echo " ./scripts/02-deploy-security.sh ${ENVIRONMENT}"
echo ""
