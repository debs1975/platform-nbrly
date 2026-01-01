#!/usr/bin/env bash

#############################################
# Configure HTTP Routing for Container App Environments
#
# This script:
# 1. Uploads SSL certificate to Container App Environment
# 2. Applies rule-based routing configuration with custom domains and SNI
# 3. Supports both NBRLY and BLOOM tenants
#
# Note: SSL/TLS is enabled end-to-end from Application Gateway through CAE to Container Apps
#
# Usage:
#   ./configure-routing.sh [nbrly|bloom|all]
#
# Requirements:
# - infra-dev.json with domain and KeyVault configuration
# - Routing template files in manifests/routing/
# - SSL certificate in Azure KeyVault
# - Container apps must be deployed before configuring routing
#############################################

set -euo pipefail

# Source logging helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh"

# Configuration paths
CONFIG_DIR="${SCRIPT_DIR}/../../config"
MANIFESTS_DIR="${SCRIPT_DIR}/../../manifests"
ROUTING_TEMPLATE_DIR="${MANIFESTS_DIR}/routing"
ROUTING_OUTPUT_DIR="${MANIFESTS_DIR}/routing"
ENV=${2:-dev}
INFRA_CONFIG="${CONFIG_DIR}/infra-${ENV}.json"

# Validate inputs
TENANT="${1:-all}"
if [[ ! "$TENANT" =~ ^(nbrly|bloom|all)$ ]]; then
    error "Invalid tenant: $TENANT. Must be 'nbrly', 'bloom', or 'all'"
    exit 1
fi

if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
    error "Invalid environment: $ENV. Must be 'dev', 'stage', or 'prod'"
    exit 1
fi

# Check required files
if [[ ! -f "$INFRA_CONFIG" ]]; then
    error "Infrastructure config not found: $INFRA_CONFIG"
    exit 1
fi

#############################################
# Function: Upload certificate to CAE from KeyVault
#############################################
upload_certificate() {
    local cae_name=$1
    local resource_group=$2
    local keyvault_name=$3
    local cert_name=$4
    
    # Log to stderr so it doesn't interfere with return value
    >&2 log "Uploading certificate '$cert_name' from KeyVault '$keyvault_name' to CAE '$cae_name'"
    
    # Check if certificate already exists in CAE
    local existing_cert
    existing_cert=$(az containerapp env certificate list \
        --name "$cae_name" \
        --resource-group "$resource_group" \
        --query "[?name=='$cert_name'].id" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$existing_cert" ]]; then
        >&2 success "Certificate already exists in CAE"
        echo "$existing_cert"
        return 0
    fi
    
    # Get KeyVault certificate secret ID
    local keyvault_cert_id
    keyvault_cert_id=$(az keyvault certificate show \
        --vault-name "$keyvault_name" \
        --name "$cert_name" \
        --query "sid" -o tsv)
    
    if [[ -z "$keyvault_cert_id" ]]; then
        >&2 error "Certificate '$cert_name' not found in KeyVault '$keyvault_name'"
        return 1
    fi
    
    >&2 log "KeyVault certificate ID: $keyvault_cert_id"
    
    # Get the managed identity for the CAE (assumes UAMI is configured)
    local cae_identity
    cae_identity=$(az containerapp env show \
        --name "$cae_name" \
        --resource-group "$resource_group" \
        --query "identity.userAssignedIdentities | keys(@)[0]" -o tsv)
    
    >&2 log "Using managed identity: $cae_identity"
    
    # Upload certificate to CAE
    cert_id=$(az containerapp env certificate upload \
        --name "$cae_name" \
        --resource-group "$resource_group" \
        --certificate-name "$cert_name" \
        --akv-url "$keyvault_cert_id" \
        --certificate-identity "$cae_identity" \
        --query "id" -o tsv 2>&1 | grep -v "WARNING" | tail -1)
    
    if [[ -n "$cert_id" ]]; then
        >&2 success "Certificate uploaded to CAE"
        echo "$cert_id"
    else
        >&2 error "Failed to upload certificate"
        return 1
    fi
}

#############################################
# Function: Configure routing for a tenant
#############################################
configure_tenant_routing() {
    local tenant=$1
    
    echo ""
    log "=========================================="
    log "Configuring routing for tenant: $tenant"
    log "=========================================="
    
    # Extract configuration from infra-dev.json
    local cae_name
    local domain
    local resource_group
    local keyvault_name
    local cert_name
    
    cae_name=$(jq -r ".containerAppEnvironments.${tenant}.name" "$INFRA_CONFIG")
    domain=$(get_tenant_value "$tenant" "$ENV" ".domain")
    resource_group=$(jq -r ".resourceGroup.name" "$INFRA_CONFIG")
    keyvault_name=$(jq -r ".keyVault.name" "$INFRA_CONFIG")
    cert_name=$(jq -r ".certificates.wildcard.certificateName" "$INFRA_CONFIG")
    
    log "CAE: $cae_name"
    log "Domain: $domain"
    log "Resource Group: $resource_group"
    log "KeyVault: $keyvault_name"
    log "Certificate: $cert_name"
    
    # Step 1: Upload SSL certificate to CAE
    log "Step 1: Upload SSL certificate to Container App Environment"
    local cert_id
    cert_id=$(upload_certificate "$cae_name" "$resource_group" "$keyvault_name" "$cert_name")
    
    if [[ -z "$cert_id" ]]; then
        error "Failed to upload certificate"
        return 1
    fi
    
    log "Certificate ID: $cert_id"
    
    # Step 2: Generate routing YAML from template
    log "Step 2: Generate routing configuration from template"
    local template_file="${ROUTING_TEMPLATE_DIR}/${tenant}-routing.yaml.template"
    local output_file="${ROUTING_OUTPUT_DIR}/${tenant}-routing.yaml"
    
    if [[ ! -f "$template_file" ]]; then
        error "Routing template not found: $template_file"
        return 1
    fi
    
    # Replace placeholders
    sed -e "s|{{CUSTOM_DOMAIN}}|${domain}|g" \
        -e "s|{{CERTIFICATE_ID}}|${cert_id}|g" \
        "$template_file" > "$output_file"
    
    success "Generated routing config: $output_file"
    
    # Step 3: Apply routing configuration
    log "Step 3: Apply HTTP routing configuration to CAE"
    
    # Route config name (can be any identifier)
    local route_config_name="${tenant}-http-routing"
    
    # Check if routing config already exists
    local existing_config
    existing_config=$(az containerapp env http-route-config show \
        --name "$cae_name" \
        --resource-group "$resource_group" \
        --http-route-config-name "$route_config_name" \
        2>/dev/null || echo "")
    
    if [[ -n "$existing_config" ]]; then
        warning "Routing config already exists, updating..."
        az containerapp env http-route-config update \
            --name "$cae_name" \
            --resource-group "$resource_group" \
            --http-route-config-name "$route_config_name" \
            --yaml "$output_file"
    else
        log "Creating new routing configuration..."
        az containerapp env http-route-config create \
            --name "$cae_name" \
            --resource-group "$resource_group" \
            --http-route-config-name "$route_config_name" \
            --yaml "$output_file"
    fi
    
    success "Routing configured for $tenant at domain: $domain"
    
    # Step 4: Show applied configuration
    log "Step 4: Verify routing configuration"
    az containerapp env http-route-config show \
        --name "$cae_name" \
        --resource-group "$resource_group" \
        --http-route-config-name "$route_config_name" \
        --output table
    
    success "Routing configuration complete for $tenant"
}

#############################################
# Main execution
#############################################
main() {
    echo ""
    log "=========================================="
    log "Container App Environment HTTP Routing Configuration"
    log "=========================================="
    log "Tenant(s): $TENANT"
    
    if [[ "$TENANT" == "all" ]]; then
        configure_tenant_routing "nbrly"
        echo ""
        configure_tenant_routing "bloom"
    else
        configure_tenant_routing "$TENANT"
    fi
    
    echo ""
    success "All routing configurations applied successfully"
    
    # Display DNS configuration reminder
    echo ""
    log "=========================================="
    log "DNS Configuration Required"
    log "=========================================="
    log "Configure DNS to point custom domains to Application Gateway public IP:"
    log ""
    
    local agw_ip
    agw_ip=$(jq -r \".applicationGateway.publicIPAddress.address\" \"$INFRA_CONFIG\")
    
    if [[ "$TENANT" == "all" || "$TENANT" == "nbrly" ]]; then
        log "NBRLY:"
        log "  A Record:   nbrly-dev.astrapia.io → $agw_ip (App Gateway)"
        log ""
    fi
    
    if [[ "$TENANT" == "all" || "$TENANT" == "bloom" ]]; then
        log "BLOOM:"
        log "  A Record:   bloom-dev.astrapia.io → $agw_ip (App Gateway)"
    fi
    
    log ""
    log "Note: SSL/TLS is enabled end-to-end from Application Gateway through CAE to Container Apps."
    log "      Both Application Gateway and Container App Environments use SSL certificates."
}

main
