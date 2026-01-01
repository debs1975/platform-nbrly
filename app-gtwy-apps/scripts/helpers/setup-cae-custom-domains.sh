#!/bin/bash

# Setup Custom Domains for Container App Environments
# Configures DNS suffix and certificate for tenant-specific custom domains

set -euo pipefail

# Determine script directory
MAIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging functions
source "$SCRIPT_DIR/logging.sh"

# Source configuration loader
source "$SCRIPT_DIR/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}
TENANT=${1:-"all"}

# Display banner
display_banner() {
    echo "================================================================================"
    log "SETUP CUSTOM DOMAINS FOR CONTAINER APP ENVIRONMENTS"
    echo "================================================================================"
    log "Purpose: Configure custom DNS suffix and SSL certificates for CAEs"
    log "Environment: $ENV"
    log "Tenant: $TENANT"
    echo "================================================================================"
    echo
}

# Setup custom domain for a specific CAE
setup_cae_custom_domain() {
    local tenant=$1
    local cae_name=$2
    local dns_suffix=$3
    local cert_file=$4
    local cert_password=$5
    local resource_group=$6
    
    log "Configuring custom domain for ${tenant} Container App Environment..."
    log "  CAE Name: $cae_name"
    log "  DNS Suffix: $dns_suffix"
    log "  Resource Group: $resource_group"
    
    # Check if CAE exists
    if ! az containerapp env show --name "$cae_name" --resource-group "$resource_group" >/dev/null 2>&1; then
        error "Container App Environment '$cae_name' not found"
        return 1
    fi
    
    # Check if certificate file exists
    if [ ! -f "$cert_file" ]; then
        error "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Update CAE with custom domain
    log "Updating Container App Environment with custom domain..."
    if az containerapp env update \
        --name "$cae_name" \
        --resource-group "$resource_group" \
        --dns-suffix "$dns_suffix" \
        --certificate-file "$cert_file" \
        --certificate-password "$cert_password" \
        --output none 2>&1; then
        success "Custom domain configured for $cae_name: $dns_suffix"
        return 0
    else
        error "Failed to configure custom domain for $cae_name"
        return 1
    fi
}

# Main execution
main() {
    display_banner
    
    # Get configuration values
    local resource_group=$(get_infra_value "$ENV" ".resourceGroup.name")
    local cert_file_path=$(jq -r '.customDomain.certificateFilePath' "$MAIN_SCRIPT_DIR/../config/parameters-${ENV}.json")
    local cert_password=${CERT_PASSWORD:-""}
    
    # Resolve certificate file path (relative to config directory)
    local cert_file="$MAIN_SCRIPT_DIR/../$cert_file_path"
    
    if [ -z "$resource_group" ]; then
        error "Resource group not found in configuration"
        exit 1
    fi
    
    # Check prerequisites
    if [ -z "$cert_password" ]; then
        error "Certificate password not provided. Set CERT_PASSWORD environment variable"
        echo
        log "Usage:"
        log "  CERT_PASSWORD='your-cert-password' $0 [tenant]"
        echo
        log "Parameters:"
        log "  tenant: 'nbrly', 'bloom', or 'all' (default: all)"
        exit 1
    fi
    
    local success_count=0
    local total_count=0
    
    # Setup NBRLY CAE
    if [ "$TENANT" = "all" ] || [ "$TENANT" = "nbrly" ]; then
        ((total_count++))
        local nbrly_cae=$(get_infra_value "$ENV" ".containerAppEnvironments.nbrly.name")
        local nbrly_domain=$(jq -r '.customDomain.tenantDomains.nbrly' "$MAIN_SCRIPT_DIR/../config/parameters-${ENV}.json")
        
        if setup_cae_custom_domain "nbrly" "$nbrly_cae" "$nbrly_domain" "$cert_file" "$cert_password" "$resource_group"; then
            ((success_count++))
        fi
        echo
    fi
    
    # Setup BLOOM CAE
    if [ "$TENANT" = "all" ] || [ "$TENANT" = "bloom" ]; then
        ((total_count++))
        local bloom_cae=$(get_infra_value "$ENV" ".containerAppEnvironments.bloom.name")
        local bloom_domain=$(jq -r '.customDomain.tenantDomains.bloom' "$MAIN_SCRIPT_DIR/../config/parameters-${ENV}.json")
        
        if setup_cae_custom_domain "bloom" "$bloom_cae" "$bloom_domain" "$cert_file" "$cert_password" "$resource_group"; then
            ((success_count++))
        fi
        echo
    fi
    
    # Summary
    log "Custom domain setup summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All Container App Environments configured successfully!"
        echo
        log "Next steps:"
        log "1. Verify DNS records point to the CAE static IPs"
        log "2. Verify custom domains:"
        if [ "$TENANT" = "all" ] || [ "$TENANT" = "nbrly" ]; then
            local nbrly_domain=$(jq -r '.customDomain.tenantDomains.nbrly' "$MAIN_SCRIPT_DIR/../config/parameters-${ENV}.json")
            log "   - NBRLY: https://$nbrly_domain"
        fi
        if [ "$TENANT" = "all" ] || [ "$TENANT" = "bloom" ]; then
            local bloom_domain=$(jq -r '.customDomain.tenantDomains.bloom' "$MAIN_SCRIPT_DIR/../config/parameters-${ENV}.json")
            log "   - BLOOM: https://$bloom_domain"
        fi
        return 0
    else
        error "Some Container App Environments failed to configure"
        return 1
    fi
}

# Run main function
main "$@"
