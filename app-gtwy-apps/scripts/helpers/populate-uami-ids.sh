#!/bin/bash

# Populate User Assigned Managed Identity IDs in configuration files
# This script retrieves actual client IDs and principal IDs from Azure

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}
RESOURCE_GROUP=${RESOURCE_GROUP:-"astra-dev-eastus-rg"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if Azure CLI is logged in
check_azure_login() {
    log "Checking Azure CLI login status..."
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure CLI. Please run: az login"
        exit 1
    fi
    success "Azure CLI login verified"
}

# Get UAMI details from Azure
get_uami_details() {
    local uami_name=$1
    local rg=$2
    
    log "Retrieving details for managed identity: $uami_name"
    
    # Get client ID and principal ID
    local client_id=$(az identity show \
        --name "$uami_name" \
        --resource-group "$rg" \
        --query clientId \
        --output tsv 2>/dev/null)
    
    local principal_id=$(az identity show \
        --name "$uami_name" \
        --resource-group "$rg" \
        --query principalId \
        --output tsv 2>/dev/null)
    
    local resource_id=$(az identity show \
        --name "$uami_name" \
        --resource-group "$rg" \
        --query id \
        --output tsv 2>/dev/null)
    
    if [ -z "$client_id" ] || [ -z "$principal_id" ] || [ -z "$resource_id" ]; then
        error "Failed to retrieve details for managed identity: $uami_name"
        return 1
    fi
    
    echo "$client_id|$principal_id|$resource_id"
}

# Update tenant configuration file with UAMI IDs
update_tenant_config() {
    local tenant=$1
    local client_id=$2
    local principal_id=$3
    local resource_id=$4
    
    local config_file="$SCRIPT_DIR/../config/$tenant/parameters-$ENV.json"
    
    if [ ! -f "$config_file" ]; then
        error "Configuration file not found: $config_file"
        return 1
    fi
    
    log "Updating configuration file: $config_file"
    
    # Create temporary file with updated values
    local temp_file=$(mktemp)
    
    jq \
        --arg client_id "$client_id" \
        --arg principal_id "$principal_id" \
        --arg resource_id "$resource_id" \
        '.managedIdentity.clientId = $client_id | 
         .managedIdentity.principalId = $principal_id |
         .managedIdentity.resourceId = $resource_id' \
        "$config_file" > "$temp_file"
    
    # Validate JSON
    if jq empty "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$config_file"
        success "Updated configuration for tenant: $tenant"
    else
        error "Invalid JSON generated for tenant: $tenant"
        rm -f "$temp_file"
        return 1
    fi
}

# Update application environment variables with AZURE_CLIENT_ID
update_app_env_vars() {
    local tenant=$1
    local client_id=$2
    
    local config_file="$SCRIPT_DIR/../config/$tenant/parameters-$ENV.json"
    
    log "Updating application environment variables for tenant: $tenant"
    
    # Create temporary file with updated values
    local temp_file=$(mktemp)
    
    # Update AZURE_CLIENT_ID in all applications
    jq \
        --arg client_id "$client_id" \
        '(.applications[] | .envVars[] | select(.name == "AZURE_CLIENT_ID") | .value) = $client_id' \
        "$config_file" > "$temp_file"
    
    # Validate JSON
    if jq empty "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$config_file"
        success "Updated AZURE_CLIENT_ID for all applications in tenant: $tenant"
    else
        error "Invalid JSON generated while updating env vars for tenant: $tenant"
        rm -f "$temp_file"
        return 1
    fi
}

# Main execution
main() {
    log "Starting UAMI ID population process"
    log "Environment: $ENV"
    log "Resource Group: $RESOURCE_GROUP"
    
    # Check prerequisites
    check_azure_login
    check_jq || exit 1
    
    # Define tenants and their UAMIs
    declare -A tenant_uamis=(
        ["nbrly"]="nbrly-dev-uami"
        ["bloom"]="bloom-dev-uami"
    )
    
    local success_count=0
    local total_count=${#tenant_uamis[@]}
    
    # Process each tenant
    for tenant in "${!tenant_uamis[@]}"; do
        local uami_name="${tenant_uamis[$tenant]}"
        
        log "Processing tenant: $tenant (UAMI: $uami_name)"
        
        # Get UAMI details from Azure
        local details=$(get_uami_details "$uami_name" "$RESOURCE_GROUP")
        
        if [ $? -eq 0 ]; then
            local client_id=$(echo "$details" | cut -d'|' -f1)
            local principal_id=$(echo "$details" | cut -d'|' -f2)
            local resource_id=$(echo "$details" | cut -d'|' -f3)
            
            log "Retrieved UAMI details:"
            log "  Client ID: $client_id"
            log "  Principal ID: $principal_id"
            log "  Resource ID: $resource_id"
            
            # Update tenant configuration
            if update_tenant_config "$tenant" "$client_id" "$principal_id" "$resource_id"; then
                # Update application environment variables
                if update_app_env_vars "$tenant" "$client_id"; then
                    ((success_count++))
                else
                    warning "Failed to update application env vars for tenant: $tenant"
                fi
            else
                warning "Failed to update configuration for tenant: $tenant"
            fi
        else
            warning "Failed to retrieve UAMI details for tenant: $tenant"
        fi
        
        echo # Empty line for readability
    done
    
    # Summary
    log "UAMI ID population summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All tenant configurations updated successfully!"
        
        log ""
        log "Updated configuration files:"
        for tenant in "${!tenant_uamis[@]}"; do
            echo "  - config/$tenant/parameters-$ENV.json"
        done
        
        log ""
        log "Next steps:"
        log "1. Review the updated configuration files"
        log "2. Deploy applications using the updated configurations"
        log "3. Verify managed identity authentication works"
        
        exit 0
    else
        error "Some tenant configurations failed to update"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Populate User Assigned Managed Identity IDs in configuration files"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -e, --env ENV        Environment (default: dev)"
    echo "  -r, --rg RG          Resource Group (default: astra-dev-eastus-rg)"
    echo
    echo "Description:"
    echo "  This script retrieves client IDs, principal IDs, and resource IDs"
    echo "  from Azure for each tenant's User Assigned Managed Identity and"
    echo "  updates the tenant configuration files accordingly."
    echo
    echo "Examples:"
    echo "  $0                                    # Use default values"
    echo "  $0 --env dev --rg my-resource-group  # Specify environment and RG"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - jq installed"
    echo "  - User Assigned Managed Identities exist in Azure"
    echo
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
