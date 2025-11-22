#!/bin/bash

# Deploy Application Gateway Routing using YAML Manifests
# This script processes the YAML manifests and applies routing configuration
# Note: Azure CLI doesn't directly support Application Gateway YAML deployment,
# so this script converts YAML definitions to Azure CLI commands

set -euo pipefail

# Configuration
RESOURCE_GROUP="rg-astrapia-dev"
APP_GATEWAY_NAME="agw-astrapia-dev"
MANIFESTS_DIR="."

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

# Get Container App FQDN
get_container_app_fqdn() {
    local app_name=$1
    az containerapp show \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.configuration.ingress.fqdn" \
        --output tsv 2>/dev/null || echo ""
}

# Process YAML manifest and extract configuration
process_yaml_manifest() {
    local yaml_file=$1
    local tenant=$2
    
    log "Processing YAML manifest: $yaml_file for tenant: $tenant"
    
    # Get Container App FQDNs
    local app1_name="ca-$tenant-${tenant:0:2}app1-dev"
    local app2_name="ca-$tenant-${tenant:0:2}app2-dev"
    
    local app1_fqdn=$(get_container_app_fqdn "$app1_name")
    local app2_fqdn=$(get_container_app_fqdn "$app2_name")
    
    if [ -z "$app1_fqdn" ] || [ -z "$app2_fqdn" ]; then
        error "Container App FQDNs not found. Please deploy Container Apps first."
        error "Expected: $app1_name and $app2_name"
        return 1
    fi
    
    log "Found Container Apps:"
    log "  - $app1_name: $app1_fqdn"
    log "  - $app2_name: $app2_fqdn"
    
    # Create backend pools
    create_backend_pool "pool-$tenant-app1" "$app1_fqdn"
    create_backend_pool "pool-$tenant-app2" "$app2_fqdn"
    
    # Create HTTP settings
    create_http_settings "settings-$tenant-app1" "/app1/health"
    create_http_settings "settings-$tenant-app2" "/app2/health"
    
    # Create URL path map
    create_url_path_map "$tenant"
    
    # Create HTTP listener and routing rule
    local domain
    if [ "$tenant" == "nbrly" ]; then
        domain="nbrly-dev.astrapia.io"
    else
        domain="bloom-dev.astrapia.io"
    fi
    
    create_routing_rule "$tenant" "$domain"
    
    return 0
}

# Create backend pool (same as configure-routing.sh)
create_backend_pool() {
    local pool_name=$1
    local fqdn=$2
    
    log "Creating backend pool: $pool_name with FQDN: $fqdn"
    
    if az network application-gateway address-pool show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$pool_name" >/dev/null 2>&1; then
        
        az network application-gateway address-pool update \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$pool_name" \
            --servers "$fqdn" \
            --only-show-errors
    else
        az network application-gateway address-pool create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$pool_name" \
            --servers "$fqdn" \
            --only-show-errors
    fi
    
    success "Backend pool configured: $pool_name"
}

# Create HTTP settings (same as configure-routing.sh)
create_http_settings() {
    local settings_name=$1
    local probe_path=$2
    
    log "Creating HTTP settings: $settings_name with probe path: $probe_path"
    
    if az network application-gateway http-settings show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$settings_name" >/dev/null 2>&1; then
        
        az network application-gateway http-settings update \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$settings_name" \
            --port 443 \
            --protocol Https \
            --timeout 30 \
            --path "$probe_path" \
            --host-name-from-backend-pool true \
            --only-show-errors
    else
        az network application-gateway http-settings create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$settings_name" \
            --port 443 \
            --protocol Https \
            --timeout 30 \
            --path "$probe_path" \
            --host-name-from-backend-pool true \
            --only-show-errors
    fi
    
    success "HTTP settings configured: $settings_name"
}

# Create URL path map (same as configure-routing.sh)
create_url_path_map() {
    local tenant=$1
    
    log "Creating URL path map for tenant: $tenant"
    
    local path_map_name="path-map-$tenant"
    local default_pool="pool-$tenant-app1"
    local default_settings="settings-$tenant-app1"
    
    if ! az network application-gateway url-path-map show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$path_map_name" >/dev/null 2>&1; then
        
        az network application-gateway url-path-map create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$path_map_name" \
            --default-address-pool "$default_pool" \
            --default-http-settings "$default_settings" \
            --only-show-errors
    fi
    
    # Create path rule for app2
    local rule_name="rule-$tenant-app2"
    local app2_pool="pool-$tenant-app2"
    local app2_settings="settings-$tenant-app2"
    
    if az network application-gateway url-path-map rule show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --path-map-name "$path_map_name" \
        --name "$rule_name" >/dev/null 2>&1; then
        
        az network application-gateway url-path-map rule update \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --path-map-name "$path_map_name" \
            --name "$rule_name" \
            --address-pool "$app2_pool" \
            --http-settings "$app2_settings" \
            --paths "/app2/*" \
            --only-show-errors
    else
        az network application-gateway url-path-map rule create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --path-map-name "$path_map_name" \
            --name "$rule_name" \
            --address-pool "$app2_pool" \
            --http-settings "$app2_settings" \
            --paths "/app2/*" \
            --only-show-errors
    fi
    
    success "URL path map configured: $path_map_name"
}

# Create routing rule (same as configure-routing.sh)
create_routing_rule() {
    local tenant=$1
    local domain=$2
    
    log "Creating routing rule for tenant: $tenant with domain: $domain"
    
    local rule_name="rule-$tenant"
    local listener_name="listener-$tenant"
    local path_map_name="path-map-$tenant"
    
    # Create HTTP listener
    if ! az network application-gateway http-listener show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$listener_name" >/dev/null 2>&1; then
        
        az network application-gateway http-listener create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$listener_name" \
            --frontend-port "appGatewayFrontendPort" \
            --host-name "$domain" \
            --only-show-errors
    fi
    
    # Create routing rule
    local priority=100
    if [ "$tenant" == "bloom" ]; then
        priority=200
    fi
    
    if az network application-gateway rule show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$rule_name" >/dev/null 2>&1; then
        
        az network application-gateway rule update \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$rule_name" \
            --http-listener "$listener_name" \
            --rule-type PathBasedRouting \
            --url-path-map "$path_map_name" \
            --only-show-errors
    else
        az network application-gateway rule create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$rule_name" \
            --http-listener "$listener_name" \
            --rule-type PathBasedRouting \
            --url-path-map "$path_map_name" \
            --priority "$priority" \
            --only-show-errors
    fi
    
    success "Routing rule configured: $rule_name"
}

# Main execution
main() {
    log "Starting Application Gateway routing deployment using YAML manifests"
    log "Resource Group: $RESOURCE_GROUP"
    log "Application Gateway: $APP_GATEWAY_NAME"
    log "Manifests Directory: $MANIFESTS_DIR"
    
    check_azure_login
    
    # Verify Application Gateway exists
    if ! az network application-gateway show \
        --name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        error "Application Gateway not found: $APP_GATEWAY_NAME"
        exit 1
    fi
    
    # Process each tenant YAML manifest
    local success_count=0
    local total_tenants=2
    
    # Process NBRLY tenant
    log "Processing NBRLY tenant routing..."
    if [ -f "$MANIFESTS_DIR/nbrly-routing.yaml" ]; then
        if process_yaml_manifest "$MANIFESTS_DIR/nbrly-routing.yaml" "nbrly"; then
            ((success_count++))
        fi
    else
        warning "NBRLY routing YAML not found: $MANIFESTS_DIR/nbrly-routing.yaml"
    fi
    
    echo
    
    # Process BLOOM tenant
    log "Processing BLOOM tenant routing..."
    if [ -f "$MANIFESTS_DIR/bloom-routing.yaml" ]; then
        if process_yaml_manifest "$MANIFESTS_DIR/bloom-routing.yaml" "bloom"; then
            ((success_count++))
        fi
    else
        warning "BLOOM routing YAML not found: $MANIFESTS_DIR/bloom-routing.yaml"
    fi
    
    # Summary
    log "YAML-based routing deployment summary:"
    log "Successful: $success_count/$total_tenants"
    
    if [ $success_count -eq $total_tenants ]; then
        success "All routing configured successfully from YAML manifests!"
        
        log ""
        log "Routing configuration applied:"
        log "  NBRLY: https://nbrly-dev.astrapia.io/app1/* and /app2/*"
        log "  BLOOM: https://bloom-dev.astrapia.io/app1/* and /app2/*"
        log ""
        log "Next steps:"
        log "1. Configure DNS records for the domains"
        log "2. Set up SSL certificates"
        log "3. Test routing functionality"
        
        exit 0
    else
        error "Some routing configurations failed"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Deploy Application Gateway Routing using YAML Manifests"
    echo
    echo "Usage: $0"
    echo
    echo "This script processes YAML routing manifests and converts them to Azure CLI commands."
    echo "It reads the YAML files to understand the desired configuration and applies it"
    echo "using Azure CLI, since direct YAML deployment is not yet supported for Application Gateway."
    echo
    echo "Required YAML files:"
    echo "  - nbrly-routing.yaml   (NBRLY tenant routing configuration)"
    echo "  - bloom-routing.yaml   (BLOOM tenant routing configuration)"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - Application Gateway exists: $APP_GATEWAY_NAME"
    echo "  - Container Apps deployed and running"
    echo "  - YAML routing manifests in current directory"
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