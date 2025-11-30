#!/bin/bash

# Configure Application Gateway Routing for Multi-Tenant Container Apps
# Sets up domain-based routing (nbrly-dev.astrapia.io, bloom-dev.astrapia.io)
# and path-based routing (/app1, /app2) for FastAPI applications
# Orchestrates routing by calling 11-configure-routing-nbrly.sh and 12-configure-routing-bloom.sh
#
# USAGE:
#   ./10-configure-routing.sh
#
# PARAMETERS:
#   None
#
# EXAMPLES:
#   ./10-configure-routing.sh             # Configure routing for all tenants
#
# PREREQUISITES:
#   - Azure CLI logged in (az login)
#   - Application Gateway exists and is running
#   - Container Apps deployed with valid FQDNs
#   - Configuration in config/infra-dev.json
#
# WORKFLOW:
#   1. Calls 11-configure-routing-nbrly.sh for NBRLY tenant
#   2. Calls 12-configure-routing-bloom.sh for BLOOM tenant
#
# CONFIGURES:
#   - Backend pools for all Container Apps
#   - HTTP settings with health probes
#   - URL path maps for path-based routing (/app1/*, /app2/*)
#   - HTTP listeners for domain-based routing
#   - Routing rules combining domain and path routing

set -euo pipefail

# Load configuration - preserve SCRIPT_DIR before config-loader redefines it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT_DIR="$SCRIPT_DIR"  # Preserve for later use
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}

# Load configuration values
check_jq || exit 1
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resourceGroup.name") # Loaded from infra-dev.json
APP_GATEWAY_NAME=$(get_infra_value "$ENV" ".applicationGateway.name") # Loaded from infra-dev.json
# Get domain names from tenant configs
NBRLY_DOMAIN=$(get_tenant_value "nbrly" "$ENV" ".domainName")
BLOOM_DOMAIN=$(get_tenant_value "bloom" "$ENV" ".domainName")

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

# Main execution
main() {
    echo "================================================================================"
    log "CONFIGURE APPLICATION GATEWAY ROUTING (ORCHESTRATOR)"
    echo "================================================================================"
    log "Purpose: Configure App Gateway routing for all tenants"
    log "         Calls 11-configure-routing-nbrly.sh and 12-configure-routing-bloom.sh"
    log "Resource Group: $RESOURCE_GROUP"
    log "Application Gateway: $APP_GATEWAY_NAME"
    log "NBRLY Domain: $NBRLY_DOMAIN"
    log "BLOOM Domain: $BLOOM_DOMAIN"
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
    
    # Configure routing for NBRLY tenant
    log "Configuring NBRLY tenant routing..."
    if "$MAIN_SCRIPT_DIR/11-configure-routing-nbrly.sh"; then
        success "NBRLY tenant routing configured"
    else
        error "Failed to configure NBRLY tenant routing"
        exit 1
    fi
    
    echo
    
    # Configure routing for BLOOM tenant
    log "Configuring BLOOM tenant routing..."
    if "$MAIN_SCRIPT_DIR/12-configure-routing-bloom.sh"; then
        success "BLOOM tenant routing configured"
    else
        error "Failed to configure BLOOM tenant routing"
        exit 1
    fi
    
    # Summary
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