#!/usr/bin/env bash
#==============================================================================
# Azure Authentication Helper
#==============================================================================
# Purpose: Authenticate to Azure using service principal credentials or
#          interactive login with automatic fallback and validation.
#
# Usage:
#   # Direct execution (recommended)
#   ./scripts/helpers/azure-login.sh [environment]
#
#   # Or source for use in other scripts
#   source scripts/helpers/azure-login.sh
#   azure_login [environment]
#
# Arguments:
#   environment (optional) - Environment name (dev, staging, prod)
#                           If not provided, uses interactive browser login
#                           If provided, attempts service principal login
#
# Credential File Format:
#   creds/azure-credentials-{env}.cred (JSON):
#   {
#     "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#     "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#     "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#     "clientSecret": "your-secret-here",
#     "environment": "dev"
#   }
#
# Environment Variables (Alternative):
#   AZURE_SUBSCRIPTION_ID
#   AZURE_TENANT_ID
#   AZURE_CLIENT_ID
#   AZURE_CLIENT_SECRET
#
# Exit Codes:
#   0 - Success (authenticated)
#   1 - Authentication failed
#   2 - Configuration error
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Color codes for output (declare only if not already set)
#------------------------------------------------------------------------------
if [[ -z "${COLOR_RED:-}" ]]; then
    readonly COLOR_RED='\033[0;31m'
fi
if [[ -z "${COLOR_GREEN:-}" ]]; then
    readonly COLOR_GREEN='\033[0;32m'
fi
if [[ -z "${COLOR_YELLOW:-}" ]]; then
    readonly COLOR_YELLOW='\033[1;33m'
fi
if [[ -z "${COLOR_BLUE:-}" ]]; then
    readonly COLOR_BLUE='\033[0;34m'
fi
if [[ -z "${COLOR_CYAN:-}" ]]; then
    readonly COLOR_CYAN='\033[0;36m'
fi
if [[ -z "${COLOR_RESET:-}" ]]; then
    readonly COLOR_RESET='\033[0m'
fi

#------------------------------------------------------------------------------
# Display authentication details
#------------------------------------------------------------------------------
display_auth_details() {
    echo ""
    echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BLUE}  Azure Authentication Details${COLOR_RESET}"
    echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
    
    # Get account details
    local account_type=$(az account show --query user.type -o tsv 2>/dev/null || echo "unknown")
    local account_name=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
    local subscription_name=$(az account show --query name -o tsv 2>/dev/null || echo "unknown")
    local subscription_id=$(az account show --query id -o tsv 2>/dev/null || echo "unknown")
    local tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null || echo "unknown")
    
    echo -e "${COLOR_GREEN}✅ Authenticated to Azure${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_BLUE}Account Information:${COLOR_RESET}"
    
    if [[ "$account_type" == "servicePrincipal" ]]; then
        echo -e "  Type: ${COLOR_CYAN}Service Principal${COLOR_RESET}"
        echo -e "  App ID (Client ID): ${COLOR_YELLOW}${account_name}${COLOR_RESET}"
        
        # Try to get the service principal display name and object ID
        local sp_name=$(az ad sp show --id "$account_name" --query displayName -o tsv 2>/dev/null || echo "N/A")
        local sp_object_id=$(az ad sp show --id "$account_name" --query id -o tsv 2>/dev/null || echo "N/A")
        
        if [[ "$sp_name" != "N/A" ]]; then
            echo -e "  Display Name: ${COLOR_CYAN}${sp_name}${COLOR_RESET}"
        fi
        if [[ "$sp_object_id" != "N/A" ]]; then
            echo -e "  Object ID: ${COLOR_YELLOW}${sp_object_id}${COLOR_RESET}"
        fi
    elif [[ "$account_type" == "user" ]]; then
        echo -e "  Type: ${COLOR_CYAN}User Account${COLOR_RESET}"
        echo -e "  User Principal Name: ${COLOR_YELLOW}${account_name}${COLOR_RESET}"
        
        # # Get user object ID (only works with user authentication, not service principal)
        # local user_object_id=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/me" --query id -o tsv 2>/dev/null || echo "N/A")
        # if [[ "$user_object_id" != "N/A" ]]; then
        #     echo -e "  Object ID: ${COLOR_YELLOW}${user_object_id}${COLOR_RESET}"
        # fi
    else
        echo -e "  Type: ${COLOR_CYAN}${account_type}${COLOR_RESET}"
        echo -e "  Name: ${COLOR_YELLOW}${account_name}${COLOR_RESET}"
    fi
    
    echo ""
    echo -e "${COLOR_BLUE}Subscription Information:${COLOR_RESET}"
    echo -e "  Name: ${COLOR_CYAN}${subscription_name}${COLOR_RESET}"
    echo -e "  Subscription ID: ${COLOR_YELLOW}${subscription_id}${COLOR_RESET}"
    echo -e "  Tenant ID: ${COLOR_YELLOW}${tenant_id}${COLOR_RESET}"
    echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

#------------------------------------------------------------------------------
# Check if already authenticated to Azure
#------------------------------------------------------------------------------
# is_authenticated() {
#     if az account show &>/dev/null; then
#         return 0
#     else
#         return 1
#     fi
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
        echo -e "${COLOR_YELLOW}⚠️  Warning: Credential file has insecure permissions ($perms)${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}   Fixing permissions to 600 (owner read-write only)...${COLOR_RESET}"
        chmod 600 "$file_path"
        echo -e "${COLOR_GREEN}   ✅ Permissions fixed${COLOR_RESET}"
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
        echo -e "${COLOR_YELLOW}⚠️  Warning: 'jq' not installed, skipping JSON validation${COLOR_RESET}"
        return 0
    fi
    
    # Validate JSON syntax
    if ! jq empty "$file_path" 2>/dev/null; then
        echo -e "${COLOR_RED}❌ Error: Invalid JSON format in credential file${COLOR_RESET}"
        return 1
    fi
    
    # Check required fields
    local required_fields=("subscriptionId" "tenantId" "clientId" "clientSecret")
    for field in "${required_fields[@]}"; do
        local value=$(jq -r ".$field // empty" "$file_path")
        if [[ -z "$value" || "$value" == "null" ]]; then
            echo -e "${COLOR_RED}❌ Error: Missing required field '$field' in credential file${COLOR_RESET}"
            return 1
        fi
        
        # Check for placeholder values
        if [[ "$value" == *"your-"* || "$value" == *"xxxx"* ]]; then
            echo -e "${COLOR_RED}❌ Error: Field '$field' contains placeholder value${COLOR_RESET}"
            echo -e "${COLOR_RED}   Please update with actual credentials${COLOR_RESET}"
            return 1
        fi
    done
    
    return 0
}

#------------------------------------------------------------------------------
# Login with service principal using credential file
#------------------------------------------------------------------------------
login_with_credential_file() {
    local env="${1:-dev}"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cred_file="$script_dir/../../creds/azure-credentials-${env}.cred"
    
    echo -e "${COLOR_BLUE}🔐 Attempting service principal login for environment: $env${COLOR_RESET}"
    
    # Check if credential file exists
    if [[ ! -f "$cred_file" ]]; then
        echo -e "${COLOR_YELLOW}⚠️  Credential file not found: $cred_file${COLOR_RESET}"
        return 1
    fi
    
    # Validate file permissions
    validate_file_permissions "$cred_file" || return 1
    
    # Validate credential file format
    validate_credential_file "$cred_file" || return 1
    
    # Read credentials from file
    local subscription_id=$(jq -r '.subscriptionId' "$cred_file")
    local tenant_id=$(jq -r '.tenantId' "$cred_file")
    local client_id=$(jq -r '.clientId' "$cred_file")
    local client_secret=$(jq -r '.clientSecret' "$cred_file")
    
    # Login with service principal
    echo -e "${COLOR_BLUE}   Authenticating with service principal...${COLOR_RESET}"
    if az login --service-principal \
        --username "$client_id" \
        --password "$client_secret" \
        --tenant "$tenant_id" \
        --output none 2>/dev/null; then
        
        # Set active subscription
        az account set --subscription "$subscription_id"
        
        # Display detailed authentication information
        display_auth_details
        return 0
    else
        echo -e "${COLOR_RED}❌ Service principal login failed${COLOR_RESET}"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Login using environment variables
#------------------------------------------------------------------------------
login_with_env_vars() {
    echo -e "${COLOR_BLUE}🔐 Attempting service principal login using environment variables${COLOR_RESET}"
    
    # Check if all required environment variables are set
    local required_vars=(
        "AZURE_SUBSCRIPTION_ID"
        "AZURE_TENANT_ID"
        "AZURE_CLIENT_ID"
        "AZURE_CLIENT_SECRET"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo -e "${COLOR_YELLOW}⚠️  Missing environment variable: $var${COLOR_RESET}"
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
        echo -e "${COLOR_RED}❌ Service principal login failed${COLOR_RESET}"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Interactive login fallback
#------------------------------------------------------------------------------
login_interactive() {
    echo -e "${COLOR_YELLOW}📝 Falling back to interactive login${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   A browser window will open for authentication...${COLOR_RESET}"
    
    if az login --output none; then
        # Display detailed authentication information
        display_auth_details
        return 0
    else
        echo -e "${COLOR_RED}❌ Interactive login failed${COLOR_RESET}"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Main authentication function
#------------------------------------------------------------------------------
azure_login() {
    local env="${1:-}"
    
    echo ""
    echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BLUE}  Azure Authentication${COLOR_RESET}"
    echo -e "${COLOR_BLUE}════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
    
    # # Check if already authenticated
    # if is_authenticated; then
    #     echo -e "${COLOR_YELLOW}⚠️  Already authenticated to Azure${COLOR_RESET}"
    #     echo -e "${COLOR_YELLOW}   Re-displaying current authentication details...${COLOR_RESET}"
    #     # Always display current authentication details
    #     display_auth_details
    #     return 0
    # fi
    
    # If no environment specified, use interactive login directly
    if [[ -z "$env" ]]; then
        echo -e "${COLOR_BLUE}ℹ️  No environment specified, using interactive browser login${COLOR_RESET}"
        echo ""
        if login_interactive; then
            # display_auth_details already called in login_interactive
            echo ""
            echo -e "${COLOR_YELLOW}💡 Tip: Pass environment name (dev/staging/prod) to use service principal${COLOR_RESET}"
            echo -e "${COLOR_YELLOW}   Example: azure_login dev${COLOR_RESET}"
            echo ""
            return 0
        else
            echo ""
            echo -e "${COLOR_RED}❌ Interactive login failed${COLOR_RESET}"
            echo ""
            return 1
        fi
    fi
    
    # Environment specified - try service principal login methods
    echo -e "${COLOR_BLUE}ℹ️  Environment specified: $env${COLOR_RESET}"
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
        echo -e "${COLOR_YELLOW}💡 Tip: Create a credential file to avoid interactive login${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}   See creds/README.md for setup instructions${COLOR_RESET}"
        echo ""
        return 0
    fi
    
    # All authentication methods failed
    echo ""
    echo -e "${COLOR_RED}❌ All authentication methods failed${COLOR_RESET}"
    echo -e "${COLOR_RED}   Please check your credentials and try again${COLOR_RESET}"
    echo ""
    return 1
}

#------------------------------------------------------------------------------
# Logout function (optional, for cleanup scripts)
#------------------------------------------------------------------------------
azure_logout() {
    echo -e "${COLOR_BLUE}🔓 Logging out from Azure...${COLOR_RESET}"
    az logout
    echo -e "${COLOR_GREEN}✅ Logged out successfully${COLOR_RESET}"
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
