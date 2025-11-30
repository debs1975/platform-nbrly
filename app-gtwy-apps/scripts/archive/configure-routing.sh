#!/bin/bash

# Configure Application Gateway Routing for Multi-Tenant Container Apps
# Sets up domain-based routing (nbrly-dev.astrapia.io, bloom-dev.astrapia.io)
# and path-based routing (/app1, /app2) for FastAPI applications

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}

# Load configuration values
check_jq || exit 1
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resources.resourceGroup.name") # Loaded from infra-dev.json
APP_GATEWAY_NAME=$(get_infra_value "$ENV" ".resources.applicationGateway.name") # Loaded from infra-dev.json
NBRLY_DOMAIN=$(get_infra_value "$ENV" ".resources.tenants.nbrly.hostName") # Loaded from infra-dev.json
BLOOM_DOMAIN=$(get_infra_value "$ENV" ".resources.tenants.bloom.hostName") # Loaded from infra-dev.json

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

# Create backend pool
create_backend_pool() {
    local pool_name=$1
    local fqdn=$2
    
    log "Creating backend pool: $pool_name with FQDN: $fqdn"
    
    if [ -z "$fqdn" ]; then
        error "FQDN not found for backend pool: $pool_name"
        return 1
    fi
    
    # Check if backend pool exists
    if az network application-gateway address-pool show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$pool_name" >/dev/null 2>&1; then
        log "Updating existing backend pool: $pool_name"
        
        az network application-gateway address-pool update \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$pool_name" \
            --servers "$fqdn" \
            --only-show-errors
    else
        log "Creating new backend pool: $pool_name"
        
        az network application-gateway address-pool create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$pool_name" \
            --servers "$fqdn" \
            --only-show-errors
    fi
    
    success "Backend pool created/updated: $pool_name"
    return 0
}

# Create HTTP settings
create_http_settings() {
    local settings_name=$1
    local root_path=$2
    
    log "Creating HTTP settings: $settings_name with root path: $root_path"
    
    # Check if HTTP settings exist
    if az network application-gateway http-settings show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$settings_name" >/dev/null 2>&1; then
        log "Updating existing HTTP settings: $settings_name"
        
        az network application-gateway http-settings update \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$settings_name" \
            --port 443 \
            --protocol Https \
            --timeout 30 \
            --path "$root_path/health" \
            --host-name-from-backend-pool true \
            --only-show-errors
    else
        log "Creating new HTTP settings: $settings_name"
        
        az network application-gateway http-settings create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$settings_name" \
            --port 443 \
            --protocol Https \
            --timeout 30 \
            --path "$root_path/health" \
            --host-name-from-backend-pool true \
            --only-show-errors
    fi
    
    success "HTTP settings created/updated: $settings_name"
    return 0
}

# Create URL path map
create_url_path_map() {
    local tenant=$1
    
    log "Creating URL path map for tenant: $tenant"
    
    local path_map_name="path-map-$tenant"
    local default_pool="pool-$tenant-app1"
    local default_settings="settings-$tenant-app1"
    
    # Create path map
    if az network application-gateway url-path-map show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$path_map_name" >/dev/null 2>&1; then
        log "URL path map already exists: $path_map_name"
    else
        log "Creating new URL path map: $path_map_name"
        
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
        log "Updating existing path rule: $rule_name"
        
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
        log "Creating new path rule: $rule_name"
        
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
    
    success "URL path map configured for tenant: $tenant"
    return 0
}

# Create routing rule
create_routing_rule() {
    local tenant=$1
    local domain=$2
    
    log "Creating routing rule for tenant: $tenant with domain: $domain"
    
    local rule_name="rule-$tenant"
    local listener_name="listener-$tenant"
    local path_map_name="path-map-$tenant"
    
    # Create HTTP listener
    if az network application-gateway http-listener show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$listener_name" >/dev/null 2>&1; then
        log "HTTP listener already exists: $listener_name"
    else
        log "Creating HTTP listener: $listener_name"
        
        az network application-gateway http-listener create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$listener_name" \
            --frontend-port "appGatewayFrontendPort" \
            --host-name "$domain" \
            --only-show-errors
    fi
    
    # Create routing rule
    if az network application-gateway rule show \
        --gateway-name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$rule_name" >/dev/null 2>&1; then
        log "Updating existing routing rule: $rule_name"
        
        az network application-gateway rule update \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$rule_name" \
            --http-listener "$listener_name" \
            --rule-type PathBasedRouting \
            --url-path-map "$path_map_name" \
            --only-show-errors
    else
        log "Creating new routing rule: $rule_name"
        
        az network application-gateway rule create \
            --gateway-name "$APP_GATEWAY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$rule_name" \
            --http-listener "$listener_name" \
            --rule-type PathBasedRouting \
            --url-path-map "$path_map_name" \
            --priority 100 \
            --only-show-errors
    fi
    
    success "Routing rule configured for tenant: $tenant"
    return 0
}

# Configure tenant routing
configure_tenant_routing() {
    local tenant=$1
    local domain=$2
    
    log "Configuring routing for tenant: $tenant"
    
    # Define applications
    declare -A apps=(
        ["app1"]="/app1"
        ["app2"]="/app2"
    )
    
    # Configure backend pools and HTTP settings for each app
    for app in "${!apps[@]}"; do
        local root_path="${apps[$app]}"
        local app_name="ca-$tenant-${app/app/}app${app: -1}-dev"
        local pool_name="pool-$tenant-$app"
        local settings_name="settings-$tenant-$app"
        
        # Get Container App FQDN
        local fqdn=$(get_container_app_fqdn "$app_name")
        
        if [ -z "$fqdn" ]; then
            warning "Container App not found: $app_name. Please deploy Container Apps first."
            continue
        fi
        
        # Create backend pool and HTTP settings
        create_backend_pool "$pool_name" "$fqdn"
        create_http_settings "$settings_name" "$root_path"
    done
    
    # Create URL path map and routing rule
    create_url_path_map "$tenant"
    create_routing_rule "$tenant" "$domain"
    
    success "Routing configured for tenant: $tenant"
    return 0
}

# Main execution
main() {
    log "Starting Application Gateway routing configuration"
    log "Resource Group: $RESOURCE_GROUP"
    log "Application Gateway: $APP_GATEWAY_NAME"
    log "NBRLY Domain: $NBRLY_DOMAIN"
    log "BLOOM Domain: $BLOOM_DOMAIN"
    
    # Check prerequisites
    check_azure_login
    
    # Verify Application Gateway exists
    if ! az network application-gateway show \
        --name "$APP_GATEWAY_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        error "Application Gateway not found: $APP_GATEWAY_NAME"
        error "Please create the Application Gateway first using infrastructure scripts"
        exit 1
    fi
    
    success "Application Gateway found: $APP_GATEWAY_NAME"
    
    # Configure routing for each tenant
    local success_count=0
    local total_tenants=2
    
    log "Configuring NBRLY tenant routing..."
    if configure_tenant_routing "nbrly" "$NBRLY_DOMAIN"; then
        ((success_count++))
    else
        warning "Failed to configure NBRLY tenant routing"
    fi
    
    echo # Empty line for readability
    
    log "Configuring BLOOM tenant routing..."
    if configure_tenant_routing "bloom" "$BLOOM_DOMAIN"; then
        ((success_count++))
    else
        warning "Failed to configure BLOOM tenant routing"
    fi
    
    # Summary
    log "Routing configuration summary:"
    log "Successful: $success_count/$total_tenants"
    
    if [ $success_count -eq $total_tenants ]; then
        success "All tenant routing configured successfully!"
        
        log ""
        log "Routing configuration completed:"
        log "NBRLY Tenant:"
        log "  - Domain: https://$NBRLY_DOMAIN"
        log "  - App1: https://$NBRLY_DOMAIN/app1/*"
        log "  - App2: https://$NBRLY_DOMAIN/app2/*"
        log ""
        log "BLOOM Tenant:"
        log "  - Domain: https://$BLOOM_DOMAIN"
        log "  - App1: https://$BLOOM_DOMAIN/app1/*"
        log "  - App2: https://$BLOOM_DOMAIN/app2/*"
        log ""
        log "Next steps:"
        log "1. Configure DNS records for the domains"
        log "2. Set up SSL certificates"
        log "3. Test the routing: ./test-routing.sh"
        
        exit 0
    else
        error "Some tenant routing configurations failed"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Configure Application Gateway Routing for Multi-Tenant Container Apps"
    echo
    echo "Usage: $0"
    echo
    echo "This script configures:"
    echo "  - Backend pools for Container Apps"
    echo "  - HTTP settings with health probes"
    echo "  - URL path maps for path-based routing"
    echo "  - HTTP listeners for domain-based routing"
    echo "  - Routing rules combining both"
    echo
    echo "Routing Configuration:"
    echo "  NBRLY Tenant ($NBRLY_DOMAIN):"
    echo "    - /app1/* -> ca-nbrly-nbapp1-dev"
    echo "    - /app2/* -> ca-nbrly-nbapp2-dev"
    echo ""
    echo "  BLOOM Tenant ($BLOOM_DOMAIN):"
    echo "    - /app1/* -> ca-bloom-bmapp1-dev"
    echo "    - /app2/* -> ca-bloom-bmapp2-dev"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - Application Gateway exists: $APP_GATEWAY_NAME"
    echo "  - Container Apps deployed and running"
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