#!/bin/bash

# Setup KeyVault Secrets for Container Apps
# Creates dummy/placeholder secrets required by Container Apps with database dependencies

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging functions
source "$SCRIPT_DIR/logging.sh"

# Source configuration loader
source "$SCRIPT_DIR/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}
TENANT=${TENANT:-"nbrly"}
KV_NAME=""

# Display banner
display_banner() {
    echo "================================================================================"
    log "SETUP KEYVAULT SECRETS FOR CONTAINER APPS"
    echo "================================================================================"
    log "Purpose: Create placeholder secrets in KeyVault for Container Apps"
    log "Environment: $ENV"
    log "Key Vault: $KV_NAME"
    echo "================================================================================"
    echo
}

# Grant Key Vault Secrets Officer role to current user/SPN
grant_keyvault_rbac() {
    local vault_name=$1
    
    log "Checking RBAC permissions for KeyVault: $vault_name"
    
    # Get current logged-in principal (user or service principal)
    local account_info
    account_info=$(az account show --query '{type: user.type, objectId: user.name}' -o json 2>/dev/null || echo "{}")
    
    # Try to get object ID from current account
    local principal_id
    principal_id=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
    
    # If user query fails, it's likely a service principal
    if [ -z "$principal_id" ]; then
        # Get SPN details from token
        local token_info
        token_info=$(az account get-access-token --query '{oid: accessToken}' -o json 2>/dev/null || echo "{}")
        
        # Decode JWT token to get object ID (oid claim)
        local access_token
        access_token=$(az account get-access-token --query accessToken -o tsv)
        
        if [ -n "$access_token" ]; then
            # Extract oid from JWT payload (base64 decode the middle part)
            principal_id=$(echo "$access_token" | cut -d'.' -f2 | base64 -d 2>/dev/null | grep -o '"oid":"[^"]*"' | cut -d'"' -f4)
        fi
    fi
    
    if [ -z "$principal_id" ]; then
        error "Unable to determine current principal ID"
        return 1
    fi
    
    log "Current principal ID: $principal_id"
    
    # Get KeyVault resource ID
    local kv_id
    kv_id=$(az keyvault show --name "$vault_name" --query id -o tsv)
    
    # Check if role assignment already exists
    local existing_role
    existing_role=$(az role assignment list \
        --assignee "$principal_id" \
        --scope "$kv_id" \
        --role "Key Vault Secrets Officer" \
        --query "[].id" -o tsv 2>/dev/null)
    
    if [ -n "$existing_role" ]; then
        success "Key Vault Secrets Officer role already assigned"
        return 0
    fi
    
    log "Granting 'Key Vault Secrets Officer' role..."
    
    # Grant the role
    if az role assignment create \
        --role "Key Vault Secrets Officer" \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type ServicePrincipal \
        --scope "$kv_id" \
        --output none 2>/dev/null; then
        success "✓ Role assigned successfully"
        log "Waiting 15 seconds for RBAC propagation..."
        sleep 15
        return 0
    else
        # Try without principal-type in case it's a user
        if az role assignment create \
            --role "Key Vault Secrets Officer" \
            --assignee "$principal_id" \
            --scope "$kv_id" \
            --output none 2>/dev/null; then
            success "✓ Role assigned successfully"
            log "Waiting 15 seconds for RBAC propagation..."
            sleep 15
            return 0
        else
            warning "Unable to assign role automatically. Please grant manually if needed."
            return 0  # Don't fail, continue anyway
        fi
    fi
}

# Check if secret exists
secret_exists() {
    local vault_name=$1
    local secret_name=$2
    
    az keyvault secret show --vault-name "$vault_name" --name "$secret_name" >/dev/null 2>&1
    return $?
}

# Create or update secret
create_secret() {
    local vault_name=$1
    local secret_name=$2
    local secret_value=$3
    local description=$4
    
    if secret_exists "$vault_name" "$secret_name"; then
        log "Secret '$secret_name' already exists, skipping..."
        return 0
    fi
    
    log "Creating secret: $secret_name"
    
    # Capture error output for debugging
    local error_output
    error_output=$(az keyvault secret set \
        --vault-name "$vault_name" \
        --name "$secret_name" \
        --value "$secret_value" \
        --description "$description" \
        --output none 2>&1)
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "Created secret: $secret_name"
        return 0
    else
        error "Failed to create secret: $secret_name"
        error "Azure CLI error: $error_output"
        return 1
    fi
}

# Setup NBRLY secrets
setup_nbrly_secrets() {
    log "Setting up NBRLY tenant secrets..."
    
    local success=0
    
    # API Key secret
    local nbrly_api_secret="nbrly-api-key"
    local nbrly_api_value="sk_nbrly_sample_api_key_$(openssl rand -hex 16)"
    if create_secret "$KV_NAME" "$nbrly_api_secret" "$nbrly_api_value" "NBRLY sample API key for testing"; then
        ((success++))
    fi
    
    # Database connection string
    local nbrly_db_secret="nbrly-psql-connection-string"
    local nbrly_db_value="postgresql://nbrly_user:PLACEHOLDER_PASSWORD@nbrly-${ENV}-psql.postgres.database.azure.com:5432/nbrlydb?sslmode=require"
    if create_secret "$KV_NAME" "$nbrly_db_secret" "$nbrly_db_value" "NBRLY PostgreSQL connection string (placeholder)"; then
        ((success++))
    fi
    
    [ $success -eq 2 ]
}

# Setup BLOOM secrets
setup_bloom_secrets() {
    log "Setting up BLOOM tenant secrets..."
    
    local success=0
    
    # API Key secret
    local bloom_api_secret="bloom-api-key"
    local bloom_api_value="sk_bloom_sample_api_key_$(openssl rand -hex 16)"
    if create_secret "$KV_NAME" "$bloom_api_secret" "$bloom_api_value" "BLOOM sample API key for testing"; then
        ((success++))
    fi
    
    # Database connection string
    local bloom_db_secret="bloom-psql-connection-string"
    local bloom_db_value="postgresql://bloom_user:PLACEHOLDER_PASSWORD@bloom-${ENV}-psql.postgres.database.azure.com:5432/bloomdb?sslmode=require"
    if create_secret "$KV_NAME" "$bloom_db_secret" "$bloom_db_value" "BLOOM PostgreSQL connection string (placeholder)"; then
        ((success++))
    fi
    
    [ $success -eq 2 ]
}

# Main execution
main() {
    display_banner
    
    # Setup secrets for the specified tenant
    local success_count=0
    local total_count=2  # 2 secrets per tenant (API key + DB connection string)
    
    # Setup secrets for the specified tenant
    KV_NAME=$(get_tenant_value "$TENANT" "$ENV" ".keyVault.name")
    
    if [ -z "$KV_NAME" ]; then
        error "$TENANT Key Vault name not found in tenant configuration"
        exit 1
    fi
    
    if ! az keyvault show --name "$KV_NAME" >/dev/null 2>&1; then
        error "$TENANT Key Vault '$KV_NAME' not found"
        exit 1
    fi
    
    success "$TENANT Key Vault '$KV_NAME' found"
    
    # Grant RBAC permissions before creating secrets
    grant_keyvault_rbac "$KV_NAME"
    
    if [ "$TENANT" = "nbrly" ]; then
        if setup_nbrly_secrets; then
            ((success_count+=2))
        fi
    elif [ "$TENANT" = "bloom" ]; then
        if setup_bloom_secrets; then
            ((success_count+=2))
        fi
    else
        error "Unknown tenant: $TENANT"
        exit 1
    fi
    
    # Summary
    echo
    log "Secret setup summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All secrets created successfully!"
        echo
        log "Secrets created:"
        if [ "$TENANT" = "nbrly" ]; then
            log "  - nbrly-api-key (sample API key)"
            log "  - nbrly-psql-connection-string (placeholder)"
        elif [ "$TENANT" = "bloom" ]; then
            log "  - bloom-api-key (sample API key)"
            log "  - bloom-psql-connection-string (placeholder)"
        fi
        echo
        log "NOTE: Database connection strings are PLACEHOLDER values."
        log "Update them with actual values once PostgreSQL servers are provisioned."
        echo
        log "To update a secret:"
        log "  az keyvault secret set --vault-name $KV_NAME --name <secret-name> --value <connection-string>"
        return 0
    else
        error "Some secrets failed to create"
        return 1
    fi
}

# Run main function
main "$@"
