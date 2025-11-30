#!/bin/bash

# Configure Application Gateway Routing for NBRLY Tenant
# Sets up domain-based routing (nbrly-dev.astrapia.io)
# and path-based routing (/app1, /app2) for FastAPI applications
#
# USAGE:
#   ./11-configure-routing-nbrly.sh
#
# PARAMETERS:
#   None
#
# EXAMPLES:
#   ./11-configure-routing-nbrly.sh       # Configure NBRLY routing only
#
# PREREQUISITES:
#   - Azure CLI logged in (az login)
#   - Application Gateway exists and is running
#   - NBRLY Container Apps deployed (ca-nbrly-nbapp1-dev, ca-nbrly-nbapp2-dev)
#   - Configuration in config/infra-dev.json
#
# CONFIGURES:
#   - Backend pools: pool-nbrly-app1, pool-nbrly-app2
#   - HTTP settings: settings-nbrly-app1, settings-nbrly-app2
#   - URL path map: path-map-nbrly with /app2/* rule
#   - HTTP listener: listener-nbrly for nbrly-dev.astrapia.io
#   - Routing rule: rule-nbrly (priority 100)

set -euo pipefail

# Load helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/logging.sh"
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}
TENANT="nbrly"

# Load configuration values
check_jq || exit 1
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resourceGroup.name")
APP_GATEWAY_NAME=$(get_infra_value "$ENV" ".applicationGateway.name")
TENANT_DOMAIN=$(get_tenant_value "nbrly" "$ENV" ".domainName")

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
    log "Creating URL path map for NBRLY tenant"
    
    local path_map_name="path-map-$TENANT"
    local default_pool="pool-$TENANT-app1"
    local default_settings="settings-$TENANT-app1"
    
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
    local rule_name="rule-$TENANT-app2"
    local app2_pool="pool-$TENANT-app2"
    local app2_settings="settings-$TENANT-app2"
    
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
    
    success "URL path map configured for NBRLY tenant"
    return 0
}

# Create routing rule
create_routing_rule() {
    log "Creating routing rule for NBRLY tenant with domain: $TENANT_DOMAIN"
    
    local rule_name="rule-$TENANT"
    local listener_name="listener-$TENANT"
    local path_map_name="path-map-$TENANT"
    
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
            --host-name "$TENANT_DOMAIN" \
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
    
    success "Routing rule configured for NBRLY tenant"
    return 0
}

# Configure NBRLY tenant routing
configure_nbrly_routing() {
    log "Configuring routing for NBRLY tenant"
    
    # Define applications
    declare -A apps=(
        ["app1"]="/app1"
        ["app2"]="/app2"
    )
    
    # Configure backend pools and HTTP settings for each app
    for app in "${!apps[@]}"; do
        local root_path="${apps[$app]}"
        local app_name="ca-$TENANT-nb${app/app/}app${app: -1}-dev"
        local pool_name="pool-$TENANT-$app"
        local settings_name="settings-$TENANT-$app"
        
        # Get Container App FQDN
        local fqdn=$(get_container_app_fqdn "$app_name")
        
        if [ -z "$fqdn" ]; then
            warning "Container App not found: $app_name. Please deploy Container Apps first."
            return 1
        fi
        
        # Create backend pool and HTTP settings
        create_backend_pool "$pool_name" "$fqdn" || return 1
        create_http_settings "$settings_name" "$root_path" || return 1
    done
    
    # Create URL path map and routing rule
    create_url_path_map || return 1
    create_routing_rule || return 1
    
    success "Routing configured for NBRLY tenant"
    return 0
}

# Main execution
main() {
    echo "================================================================================"
    log "CONFIGURE NBRLY TENANT ROUTING"
    echo "================================================================================"
    log "Purpose: Configure Application Gateway routing for NBRLY tenant"
    log "Resource Group: $RESOURCE_GROUP"
    log "Application Gateway: $APP_GATEWAY_NAME"
    log "NBRLY Domain: $TENANT_DOMAIN"
    echo "================================================================================"
    echo
    
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
    
    # Configure NBRLY tenant routing
    if configure_nbrly_routing; then
        success "NBRLY tenant routing configured successfully!"
        
        log ""
        log "Routing configuration completed:"
        log "NBRLY Tenant:"
        log "  - Domain: https://$TENANT_DOMAIN"
        log "  - App1: https://$TENANT_DOMAIN/app1/*"
        log "  - App2: https://$TENANT_DOMAIN/app2/*"
        log ""
        log "Next steps:"
        log "1. Configure DNS records for $TENANT_DOMAIN"
        log "2. Set up SSL certificates"
        log "3. Test the routing"
        
        exit 0
    else
        error "Failed to configure NBRLY tenant routing"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Configure Application Gateway Routing for NBRLY Tenant"
    echo
    echo "Usage: $0"
    echo
    echo "This script configures:"
    echo "  - Backend pools for NBRLY Container Apps"
    echo "  - HTTP settings with health probes"
    echo "  - URL path maps for path-based routing"
    echo "  - HTTP listeners for domain-based routing"
    echo "  - Routing rules combining both"
    echo
    echo "Routing Configuration:"
    echo "  NBRLY Tenant ($TENANT_DOMAIN):"
    echo "    - /app1/* -> ca-nbrly-nbapp1-dev"
    echo "    - /app2/* -> ca-nbrly-nbapp2-dev"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - Application Gateway exists: $APP_GATEWAY_NAME"
    echo "  - NBRLY Container Apps deployed and running"
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
