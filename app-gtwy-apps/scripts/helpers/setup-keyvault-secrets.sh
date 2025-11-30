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
    if az keyvault secret set \
        --vault-name "$vault_name" \
        --name "$secret_name" \
        --value "$secret_value" \
        --description "$description" \
        --output none 2>/dev/null; then
        success "Created secret: $secret_name"
        return 0
    else
        error "Failed to create secret: $secret_name"
        return 1
    fi
}

# Setup NBRLY secrets
setup_nbrly_secrets() {
    log "Setting up NBRLY tenant secrets..."
    
    local nbrly_db_secret="nbrly-psql-connection-string"
    local nbrly_db_value="postgresql://nbrly_user:PLACEHOLDER_PASSWORD@nbrly-dev-psql.postgres.database.azure.com:5432/nbrlydb?sslmode=require"
    
    create_secret "$KV_NAME" "$nbrly_db_secret" "$nbrly_db_value" "NBRLY PostgreSQL connection string (placeholder)"
}

# Setup BLOOM secrets
setup_bloom_secrets() {
    log "Setting up BLOOM tenant secrets..."
    
    local bloom_db_secret="bloom-psql-connection-string"
    local bloom_db_value="postgresql://bloom_user:PLACEHOLDER_PASSWORD@bloom-dev-psql.postgres.database.azure.com:5432/bloomdb?sslmode=require"
    
    create_secret "$KV_NAME" "$bloom_db_secret" "$bloom_db_value" "BLOOM PostgreSQL connection string (placeholder)"
}

# Main execution
main() {
    # Get Key Vault name from infra config
    KV_NAME=$(get_infra_value "$ENV" ".resources.keyVault.name")
    
    if [ -z "$KV_NAME" ]; then
        error "Key Vault name not found in configuration"
        exit 1
    fi
    
    display_banner
    
    # Check if Key Vault exists
    if ! az keyvault show --name "$KV_NAME" >/dev/null 2>&1; then
        error "Key Vault '$KV_NAME' not found"
        exit 1
    fi
    
    success "Key Vault '$KV_NAME' found"
    
    # Setup secrets for both tenants
    local success_count=0
    local total_count=2
    
    if setup_nbrly_secrets; then
        ((success_count++))
    fi
    
    if setup_bloom_secrets; then
        ((success_count++))
    fi
    
    # Summary
    echo
    log "Secret setup summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All secrets created successfully!"
        echo
        log "NOTE: These are PLACEHOLDER values. Update them with actual database"
        log "connection strings once the PostgreSQL servers are provisioned."
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
