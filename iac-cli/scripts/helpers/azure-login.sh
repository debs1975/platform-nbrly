#!/usr/bin/env bash
#==============================================================================
# Azure Authentication Helper
#==============================================================================
# Purpose: Authenticate to Azure using service principal credentials or
# interactive login with automatic fallback and validation.
#
# Usage:
# # Direct execution (recommended)
# ./scripts/helpers/azure-login.sh [environment]
#
# # Or source for use in other scripts
# source scripts/helpers/azure-login.sh
# azure_login [environment]
#
# Arguments:
# environment (optional) - Environment name (dev, staging, prod)
# If not provided, uses interactive browser login
# If provided, attempts service principal login
#
# Credential File Format:
# creds/azure-credentials-{env}.cred (JSON):
# {
# "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
# "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
# "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
# "clientSecret": "your-secret-here",
# "environment": "dev"
# }
#
# Environment Variables (Alternative):
# AZURE_SUBSCRIPTION_ID
# AZURE_TENANT_ID
# AZURE_CLIENT_ID
# AZURE_CLIENT_SECRET
#
# Exit Codes:
# 0 - Success (authenticated)
# 1 - Authentication failed
# 2 - Configuration error
#==============================================================================
set -euo pipefail
#------------------------------------------------------------------------------
# Color codes for output (declare only if not already set)
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
# Display authentication details
#------------------------------------------------------------------------------
display_auth_details() {
 echo ""
 echo "════════════════════════════════════════════════════════════"
 echo " Azure Authentication Details"
 echo "════════════════════════════════════════════════════════════"
 # Get account details
 local account_type=$(az account show --query user.type -o tsv 2>/dev/null || echo "unknown")
 local account_name=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
 local subscription_name=$(az account show --query name -o tsv 2>/dev/null || echo "unknown")
 local subscription_id=$(az account show --query id -o tsv 2>/dev/null || echo "unknown")
 local tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null || echo "unknown")
 echo "✅ Authenticated to Azure"
 echo ""
 echo "Account Information:"
 if [[ "$account_type" == "servicePrincipal" ]]; then
 echo " Type: Service Principal"
 echo " App ID (Client ID): ${account_name}"
 # Try to get the service principal display name and object ID
 local sp_name=$(az ad sp show --id "$account_name" --query displayName -o tsv 2>/dev/null || echo "N/A")
 local sp_object_id=$(az ad sp show --id "$account_name" --query id -o tsv 2>/dev/null || echo "N/A")
 if [[ "$sp_name" != "N/A" ]]; then
 echo " Display Name: ${sp_name}"
 fi
 if [[ "$sp_object_id" != "N/A" ]]; then
 echo " Object ID: ${sp_object_id}"
 fi
 elif [[ "$account_type" == "user" ]]; then
 echo " Type: User Account"
 echo " User Principal Name: ${account_name}"
 # # Get user object ID (only works with user authentication, not service principal)
 # local user_object_id=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/me" --query id -o tsv 2>/dev/null || echo "N/A")
 # if [[ "$user_object_id" != "N/A" ]]; then
 # echo " Object ID: ${user_object_id}"
 # fi
 else
 echo " Type: ${account_type}"
 echo " Name: ${account_name}"
 fi
 echo ""
 echo "Subscription Information:"
 echo " Name: ${subscription_name}"
 echo " Subscription ID: ${subscription_id}"
 echo " Tenant ID: ${tenant_id}"
 echo "════════════════════════════════════════════════════════════"
 echo ""
}
#------------------------------------------------------------------------------
# Check if already authenticated to Azure
#------------------------------------------------------------------------------
# is_authenticated() {
# if az account show &>/dev/null; then
# return 0
# else
# return 1
# fi
# }
#------------------------------------------------------------------------------
# Validate credential file permissions (should be 600 for security)
#------------------------------------------------------------------------------
validate_file_permissions() {
 local file_path="$1"
 if [[ ! -f "$file_path" ]]; then
 return 1
 fi
 # Get file permissions (macOS and Linux compatible)
 if [[ "$OSTYPE" == "darwin"* ]]; then
 # macOS
 local perms=$(stat -f "%A" "$file_path")
 else
 # Linux
 local perms=$(stat -c "%a" "$file_path")
 fi
 # Check if permissions are too open (should be 600 or stricter)
 if [[ "$perms" != "600" && "$perms" != "400" ]]; then
 echo "⚠️ Warning: Credential file has insecure permissions ($perms)"
 echo " Fixing permissions to 600 (owner read-write only)..."
 chmod 600 "$file_path"
 echo " ✅ Permissions fixed"
 fi
 return 0
}
#------------------------------------------------------------------------------
# Validate JSON credential file format
#------------------------------------------------------------------------------
validate_credential_file() {
 local file_path="$1"
 # Check if jq is available for JSON parsing
 if ! command -v jq &>/dev/null; then
 echo "❌ Error: 'jq' is required for credential file parsing but not installed"
 echo " Please install jq: brew install jq (macOS) or apt-get install jq (Ubuntu)"
 return 1
 fi
 # Validate JSON syntax
 if ! jq empty "$file_path" 2>/dev/null; then
 echo "❌ Error: Invalid JSON format in credential file: $file_path"
 return 1
 fi
 # Check required fields
 local required_fields=("subscriptionId" "tenantId" "clientId" "clientSecret")
 for field in "${required_fields[@]}"; do
 local value=$(jq -r ".$field // empty" "$file_path")
 if [[ -z "$value" || "$value" == "null" ]]; then
 echo "❌ Error: Missing required field '$field' in credential file"
 return 1
 fi
 # Check for placeholder values
 if [[ "$value" == *"your-"* || "$value" == *"xxxx"* ]]; then
 echo "❌ Error: Field '$field' contains placeholder value"
 echo " Please update with actual credentials"
 return 1
 fi
 done
 return 0
}
#------------------------------------------------------------------------------
# Login with service principal using credential file
login_with_credential_file() {
 local env="${1:-dev}"
 local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 local cred_file="$script_dir/../../creds/azure-credentials-${env}.cred"
 
 echo "🔐 Attempting service principal login for environment: $env"
 echo "📁 Looking for credential file at: $cred_file"
 
 # Check if credential file exists
 if [[ ! -f "$cred_file" ]]; then
 echo "⚠️ Credential file not found: $cred_file"
 echo " Expected format: JSON with subscriptionId, tenantId, clientId, clientSecret"
 return 1
 fi
 # Validate file permissions
 if ! validate_file_permissions "$cred_file"; then
 echo "❌ Error: Failed to validate credential file permissions"
 return 1
 fi
 # Validate credential file format
 if ! validate_credential_file "$cred_file"; then
 echo "❌ Error: Credential file validation failed"
 return 1
 fi
 # Read credentials from file
 local subscription_id=$(jq -r '.subscriptionId' "$cred_file")
 local tenant_id=$(jq -r '.tenantId' "$cred_file")
 local client_id=$(jq -r '.clientId' "$cred_file")
 local client_secret=$(jq -r '.clientSecret' "$cred_file")
 # Login with service principal
 echo " Authenticating with service principal..."
 echo " Client ID: ${client_id:0:8}..."
 echo " Tenant ID: ${tenant_id:0:8}..."
 
 # Capture login error for better debugging
 local login_error
 if login_error=$(az login --service-principal \
 --username "$client_id" \
 --password "$client_secret" \
 --tenant "$tenant_id" \
 --output none 2>&1); then
 # Set active subscription
 az account set --subscription "$subscription_id"
 echo "✅ Service principal authentication successful"
 # Display detailed authentication information
 display_auth_details
 return 0
 else
 echo "❌ Service principal login failed"
 echo " Error details: ${login_error}"
 echo " Please verify:"
 echo "  - Client ID is correct"
 echo "  - Client secret is valid and not expired"
 echo "  - Service principal has access to the subscription"
 echo "  - Tenant ID is correct"
 return 1
 fi
}
#------------------------------------------------------------------------------
# Login using environment variables
#------------------------------------------------------------------------------
login_with_env_vars() {
 echo "🔐 Attempting service principal login using environment variables"
 # Check if all required environment variables are set
 local required_vars=(
 "AZURE_SUBSCRIPTION_ID"
 "AZURE_TENANT_ID"
 "AZURE_CLIENT_ID"
 "AZURE_CLIENT_SECRET"
 )
 for var in "${required_vars[@]}"; do
 if [[ -z "${!var:-}" ]]; then
 echo "⚠️ Missing environment variable: $var"
 return 1
 fi
 done
 # Login with service principal
 if az login --service-principal \
 --username "$AZURE_CLIENT_ID" \
 --password "$AZURE_CLIENT_SECRET" \
 --tenant "$AZURE_TENANT_ID" \
 --output none 2>/dev/null; then
 # Set active subscription
 az account set --subscription "$AZURE_SUBSCRIPTION_ID"
 # Display detailed authentication information
 display_auth_details
 return 0
 else
 echo "❌ Service principal login failed"
 return 1
 fi
}
#------------------------------------------------------------------------------
# Interactive login fallback
#------------------------------------------------------------------------------
login_interactive() {
 echo "📝 Falling back to interactive login"
 echo " A browser window will open for authentication..."
 if az login --output none; then
 # Display detailed authentication information
 display_auth_details
 return 0
 else
 echo "❌ Interactive login failed"
 return 1
 fi
}
#------------------------------------------------------------------------------
# Main authentication function
#------------------------------------------------------------------------------
azure_login() {
 local env="${1:-}"
 echo ""
 echo "════════════════════════════════════════════════════════════"
 echo " Azure Authentication"
 echo "════════════════════════════════════════════════════════════"
 echo ""
 # # Check if already authenticated
 # if is_authenticated; then
 # echo "⚠️ Already authenticated to Azure"
 # echo " Re-displaying current authentication details..."
 # # Always display current authentication details
 # display_auth_details
 # return 0
 # fi
 # If no environment specified, use interactive login directly
 if [[ -z "$env" ]]; then
 echo "ℹ️ No environment specified, using interactive browser login"
 echo ""
 if login_interactive; then
 # display_auth_details already called in login_interactive
 echo ""
 echo "💡 Tip: Pass environment name (dev/staging/prod) to use service principal"
 echo " Example: azure_login dev"
 echo ""
 return 0
 else
 echo ""
 echo "❌ Interactive login failed"
 echo ""
 return 1
 fi
 fi
 # Environment specified - try service principal login methods
 echo "ℹ️ Environment specified: $env"
 echo ""
 # Try credential file first
 if login_with_credential_file "$env"; then
 # display_auth_details already called in login_with_credential_file
 return 0
 fi
 # Try environment variables second
 if login_with_env_vars; then
 # display_auth_details already called in login_with_env_vars
 return 0
 fi
 # Fall back to interactive login
 if login_interactive; then
 # display_auth_details already called in login_interactive
 echo ""
 echo "💡 Tip: Create a credential file to avoid interactive login"
 echo " See creds/README.md for setup instructions"
 echo ""
 return 0
 fi
 # All authentication methods failed
 echo ""
 echo "❌ All authentication methods failed"
 echo " Please check your credentials and try again"
 echo ""
 return 1
}
#------------------------------------------------------------------------------
# Logout function (optional, for cleanup scripts)
#------------------------------------------------------------------------------
azure_logout() {
 echo "🔓 Logging out from Azure..."
 az logout
 echo "✅ Logged out successfully"
}
#------------------------------------------------------------------------------
# Export functions for use in sourcing scripts
#------------------------------------------------------------------------------
export -f azure_login
export -f azure_logout
# export -f is_authenticated
export -f display_auth_details
#------------------------------------------------------------------------------
# Main execution (only runs when script is executed directly, not sourced)
#------------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 # Script is being executed directly
 azure_login "${1:-}"
 exit $?
fi
