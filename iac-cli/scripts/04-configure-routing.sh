#!/bin/bash

# ============================================================================
# Configure Application Gateway Routing for Tenant
# ============================================================================
# This script configures Application Gateway routing rules for a specific tenant
# It creates backend pools, HTTP settings, listeners, and routing rules
# 
# Usage: ./04-configure-routing.sh <tenant_name> <environment>
# Example: ./04-configure-routing.sh nbrly dev
# Example: ./04-configure-routing.sh bloom dev
# ============================================================================

set -euo pipefail

# Cleanup function
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Get script directory and source helpers
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# Source helper functions
source "${SCRIPT_DIR}/helpers/logging.sh"
source "${SCRIPT_DIR}/helpers/azure-login.sh"
source "${SCRIPT_DIR}/helpers/config-parser.sh"

# Error handler
error_handler() {
    log_error "Script failed at line $1 with exit code $2"
    log_error "Command: ${BASH_COMMAND}"
}
trap 'error_handler $LINENO $?' ERR

# Function definitions
usage() {
    echo "Usage: $SCRIPT_NAME <tenant_name> <environment>"
    echo ""
    echo "Arguments:"
    echo "  tenant_name    Name of the tenant (nbrly, bloom)"
    echo "  environment    Environment (dev, stage, prod)"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME nbrly dev"
    echo "  $SCRIPT_NAME bloom dev"
    exit 0
}

validate_requirements() {
    if [[ -z "$TENANT_NAME" ]]; then
        log_error "Tenant name is required"
        usage
    fi
    
    if [[ ! "$TENANT_NAME" =~ ^(nbrly|bloom)$ ]]; then
        log_error "Invalid tenant: $TENANT_NAME (must be 'nbrly' or 'bloom')"
        usage
    fi
    
    if [[ ! "$ENVIRONMENT" =~ ^(dev|stage|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT (must be dev, stage, or prod)"
        usage
    fi
    
    if [[ ! -f "$INFRA_FILE" ]]; then
        log_error "Infrastructure configuration file not found: $INFRA_FILE"
        exit 1
    fi
    
    if [[ ! -f "$TENANT_CONFIG_FILE" ]]; then
        log_error "Tenant configuration file not found: $TENANT_CONFIG_FILE"
        exit 1
    fi
}

# Parse command line arguments
TENANT_NAME="${1:-}"
ENVIRONMENT="${2:-dev}"

if [[ "$TENANT_NAME" == "-h" || "$TENANT_NAME" == "--help" ]]; then
    usage
fi

# Configuration files
readonly CONFIG_DIR="${SCRIPT_DIR}/../config"
readonly INFRA_FILE="${CONFIG_DIR}/infra-${ENVIRONMENT}.json"
readonly TENANT_CONFIG_FILE="${CONFIG_DIR}/${TENANT_NAME}/parameters-${ENVIRONMENT}.json"

# Validate requirements
validate_requirements

# Load configuration
log_info "Loading configuration for tenant '$TENANT_NAME' in environment '$ENVIRONMENT'"

# Parse infrastructure configuration
SUBSCRIPTION_ID=$(parse_config "$INFRA_FILE" ".subscription.id")
RESOURCE_GROUP=$(parse_config "$INFRA_FILE" ".resourceGroup.name")
LOCATION=$(parse_config "$INFRA_FILE" ".location")
APPGW_NAME=$(parse_config "$INFRA_FILE" ".applicationGateway.name")
SSL_CERT_NAME=$(parse_config "$INFRA_FILE" ".applicationGateway.sslCertificateName" 2>/dev/null || echo "")

# If SSL certificate name is not in config, retrieve it from Application Gateway quietly
if [[ -z "$SSL_CERT_NAME" ]]; then
    SSL_CERT_NAME=$(az network application-gateway ssl-cert list \
        --gateway-name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null || echo "astrapiaio")
fi

# Parse tenant configuration  
DOMAIN_NAME=$(parse_config "$TENANT_CONFIG_FILE" ".domain")
CAE_NAME=$(parse_config "$TENANT_CONFIG_FILE" ".containerAppEnvironment.name")
CAE_STATIC_IP=$(parse_config "$TENANT_CONFIG_FILE" ".containerAppEnvironment.staticIp")
CAE_DEFAULT_DOMAIN=$(parse_config "$TENANT_CONFIG_FILE" ".containerAppEnvironment.defaultDomain")

# Validate required values
if [[ -z "$CAE_STATIC_IP" || "$CAE_STATIC_IP" == "null" ]]; then
    log_error "Container App Environment static IP not found for tenant: $TENANT_NAME"
    log_error "Please run: ./03-deploy-tenant-resources.sh $TENANT_NAME $ENVIRONMENT"
    exit 1
fi

if [[ -z "$CAE_DEFAULT_DOMAIN" || "$CAE_DEFAULT_DOMAIN" == "null" ]]; then
    log_error "Container App Environment default domain not found for tenant: $TENANT_NAME"
    log_error "Please run: ./03-deploy-tenant-resources.sh $TENANT_NAME $ENVIRONMENT"
    exit 1
fi

# Construct backend pool FQDN: <cae-name>.<defaultDomain>
BACKEND_POOL_FQDN="${CAE_NAME}.${CAE_DEFAULT_DOMAIN}"

# Derived resource names (following naming convention with environment)
readonly BACKEND_POOL_NAME="${TENANT_NAME}-${ENVIRONMENT}-bp"
readonly HTTP_LISTENER_NAME="${TENANT_NAME}-${ENVIRONMENT}-hl"
readonly HEALTH_PROBE_NAME="${TENANT_NAME}-${ENVIRONMENT}-probe"
readonly HTTP_SETTINGS_NAME="${TENANT_NAME}-${ENVIRONMENT}-https"
readonly ROUTING_RULE_NAME="${TENANT_NAME}-${ENVIRONMENT}-rr"

# Display configuration
log_info "========================================================================="
log_info "Application Gateway Routing Configuration"
log_info "========================================================================="
log_info "Tenant:              $TENANT_NAME"
log_info "Environment:         $ENVIRONMENT"
log_info "Domain:              $DOMAIN_NAME"
log_info "Application Gateway: $APPGW_NAME"
log_info "CAE:                 $CAE_NAME"
log_info "Backend Pool FQDN:    $BACKEND_POOL_FQDN"
log_info "Backend Static IP:   $CAE_STATIC_IP"
log_info "========================================================================="

TEMP_DIR=""

main() {
    validate_requirements

    TEMP_DIR="$(mktemp -d)"
    if [[ ! -d "$TEMP_DIR" ]]; then
        log_error "Failed to create temporary directory" >&2
        exit 1
    fi

    log_info "========================================================================="
    log_info "Starting Application Gateway Configuration"
    log_info "========================================================================="

    # Login to Azure with environment-specific credentials
    azure_login "$ENVIRONMENT"
    
    # Set Azure subscription
    if [ -n "$SUBSCRIPTION_ID" ] && [ "$SUBSCRIPTION_ID" != "null" ]; then
        log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    else
        log_warning "No subscription ID found in infra file. Using current subscription context."
        CURRENT_SUBSCRIPTION=$(az account show --query "id" -o tsv 2>/dev/null || echo "")
        if [ -n "$CURRENT_SUBSCRIPTION" ]; then
            log_info "Current subscription: $CURRENT_SUBSCRIPTION"
            SUBSCRIPTION_ID="$CURRENT_SUBSCRIPTION"
        else
            log_error "No subscription context available. Please ensure you're logged in and have a valid subscription."
            exit 1
        fi
    fi

    log_info ""
    log_info "┌────────────────────────────────────────────────────────────────────────────────┐"
    log_info "│ STEP 1: Creating Backend Pool                                                  │"
    log_info "└────────────────────────────────────────────────────────────────────────────────┘"
    log_info ""
    log_info "  Backend Pool Configuration:"
    log_info "    • Name:                $BACKEND_POOL_NAME"
    log_info "    • Backend FQDN:        $BACKEND_POOL_FQDN"
    log_info "    • Application Gateway: $APPGW_NAME"
    log_info "    • Tenant:              $TENANT_NAME"
    log_info ""

    # 1. Create/Update Backend Pool
    log_info "Configuring backend pool: $BACKEND_POOL_NAME"
    if az network application-gateway address-pool show \
        --gateway-name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BACKEND_POOL_NAME" &>/dev/null; then
        log_info "Updating existing backend pool with FQDN: $BACKEND_POOL_FQDN"
        az network application-gateway address-pool update \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$BACKEND_POOL_NAME" \
            --servers "$BACKEND_POOL_FQDN"
    else
        log_info "Creating new backend pool with FQDN: $BACKEND_POOL_FQDN"
        az network application-gateway address-pool create \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$BACKEND_POOL_NAME" \
            --servers "$BACKEND_POOL_FQDN"
    fi
    log_success "Backend pool configured: $BACKEND_POOL_NAME"

    log_info ""
    log_info "┌────────────────────────────────────────────────────────────────────────────────┐"
    log_info "│ STEP 2: Creating HTTP Settings                                                 │"
    log_info "└────────────────────────────────────────────────────────────────────────────────┘"
    log_info ""
    log_info "  HTTP Settings Configuration:"
    log_info "    • Name:                $HTTP_SETTINGS_NAME"
    log_info "    • Port:                443"
    log_info "    • Protocol:            HTTPS"
    log_info "    • Host override:       From backend target"
    log_info "    • Cookie Affinity:     Disabled"
    log_info "    • Tenant:              $TENANT_NAME"
    log_info ""

    # 2. Create/Update HTTP Settings (without probe first)
    log_info "Configuring HTTP settings: $HTTP_SETTINGS_NAME"
    if az network application-gateway http-settings show \
        --gateway-name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HTTP_SETTINGS_NAME" &>/dev/null; then
        log_info "Updating existing HTTP settings to pick hostname from backend target"
        # First, remove any explicit hostname to avoid conflict
        az network application-gateway http-settings update \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HTTP_SETTINGS_NAME" \
            --host-name "" \
            --no-wait
        # Then set to pick hostname from backend pool
        az network application-gateway http-settings update \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HTTP_SETTINGS_NAME" \
            --port 443 \
            --protocol "Https" \
            --host-name-from-backend-pool true
    else
        log_info "Creating new HTTP settings to pick hostname from backend target"
        az network application-gateway http-settings create \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HTTP_SETTINGS_NAME" \
            --port 443 \
            --protocol "Https" \
            --host-name-from-backend-pool true
    fi
    log_success "HTTP settings configured: $HTTP_SETTINGS_NAME"

    log_info ""
    log_info "┌────────────────────────────────────────────────────────────────────────────────┐"
    log_info "│ STEP 3: Creating Health Probe                                                  │"
    log_info "└────────────────────────────────────────────────────────────────────────────────┘"
    log_info ""
    log_info "  Health Probe Configuration:"
    log_info "    • Name:                $HEALTH_PROBE_NAME"
    log_info "    • Port:                443"
    log_info "    • Protocol:            HTTPS"
    log_info "    • Pick hostname:       From backend settings"
    log_info "    • Tenant:              $TENANT_NAME"
    log_info ""

    # 3. Create/Update Health Probe
    log_info "Configuring health probe: $HEALTH_PROBE_NAME"
    if az network application-gateway probe show \
        --gateway-name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HEALTH_PROBE_NAME" &>/dev/null; then
        log_info "Updating existing health probe to pick hostname from backend settings"
        # Update probe to remove explicit host and set to pick from backend settings in single command
        az network application-gateway probe update \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HEALTH_PROBE_NAME" \
            --protocol "Https" \
            --host-name-from-http-settings true \
            --host "" \
            --path "/"
    else
        log_info "Creating new health probe to pick hostname from backend settings"
        az network application-gateway probe create \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HEALTH_PROBE_NAME" \
            --protocol "Https" \
            --host-name-from-http-settings true \
            --path "/" \
            --interval 30 \
            --timeout 30 \
            --threshold 3
    fi
    log_success "Health probe configured: $HEALTH_PROBE_NAME"

    log_info ""
    log_info "┌────────────────────────────────────────────────────────────────────────────────┐"
    log_info "│ STEP 3.5: Associating Health Probe with HTTP Settings                          │"
    log_info "└────────────────────────────────────────────────────────────────────────────────┘"
    log_info ""

    # 3.5. Associate probe with HTTP settings
    log_info "Associating health probe with HTTP settings"
    az network application-gateway http-settings update \
        --gateway-name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HTTP_SETTINGS_NAME" \
        --probe "$HEALTH_PROBE_NAME"
    log_success "Health probe associated with HTTP settings"

    log_info ""
    log_info "┌────────────────────────────────────────────────────────────────────────────────┐"
    log_info "│ STEP 4: Creating HTTPS Listener                                                │"
    log_info "└────────────────────────────────────────────────────────────────────────────────┘"
    log_info ""
    log_info "  HTTPS Listener Configuration:"
    log_info "    • Name:                $HTTP_LISTENER_NAME"
    log_info "    • Frontend Port:       443 (HTTPS)"
    log_info "    • Certificate:         astrapiaio"
    log_info "    • Application Gateway: $APPGW_NAME"
    log_info "    • Tenant:              $TENANT_NAME"
    log_info ""

    # 4. Create/Update HTTPS Listener
    log_info "Configuring HTTPS listener: $HTTP_LISTENER_NAME"
    if az network application-gateway http-listener show \
        --gateway-name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HTTP_LISTENER_NAME" &>/dev/null; then
        log_info "Updating existing HTTPS listener"
        az network application-gateway http-listener update \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HTTP_LISTENER_NAME" \
            --frontend-port "port_443" \
            --host-name "$DOMAIN_NAME" \
            --ssl-cert "$SSL_CERT_NAME"
    else
        log_info "Creating new HTTPS listener"
        az network application-gateway http-listener create \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HTTP_LISTENER_NAME" \
            --frontend-port "port_443" \
            --host-name "$DOMAIN_NAME" \
            --ssl-cert "$SSL_CERT_NAME"
    fi
    log_success "HTTPS listener configured: $HTTP_LISTENER_NAME"

    log_info ""
    log_info "┌────────────────────────────────────────────────────────────────────────────────┐"
    log_info "│ STEP 5: Creating Routing Rule                                                  │"
    log_info "└────────────────────────────────────────────────────────────────────────────────┘"
    log_info ""
    log_info "  Routing Rule Configuration:"
    log_info "    • Name:                $ROUTING_RULE_NAME"
    log_info "    • Path:                /$TENANT_NAME"
    log_info "    • Backend Pool:        $BACKEND_POOL_NAME"
    log_info "    • HTTP Settings:       $HTTP_SETTINGS_NAME"
    log_info "    • Tenant:              $TENANT_NAME"
    log_info ""

    # 5. Create/Update Routing Rule
    log_info "Configuring routing rule: $ROUTING_RULE_NAME"
    if az network application-gateway rule show \
        --gateway-name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ROUTING_RULE_NAME" &>/dev/null; then
        log_info "Routing rule already exists: $ROUTING_RULE_NAME"
    else
        log_info "Creating new routing rule"
        
        # Get existing priorities and calculate next available one
        EXISTING_PRIORITIES=$(az network application-gateway rule list \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].priority" -o tsv 2>/dev/null | sort -n)
        
        # Calculate priority based on tenant name to avoid conflicts
        case "$TENANT_NAME" in
            "nbrly") BASE_PRIORITY=1000 ;;
            "bloom") BASE_PRIORITY=2000 ;;
            *) BASE_PRIORITY=5000 ;;
        esac
        
        # Find next available priority starting from base
        PRIORITY=$BASE_PRIORITY
        while echo "$EXISTING_PRIORITIES" | grep -q "^${PRIORITY}$"; do
            PRIORITY=$((PRIORITY + 10))
        done
        
        log_info "Using priority: $PRIORITY"
        
        az network application-gateway rule create \
            --gateway-name "$APPGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$ROUTING_RULE_NAME" \
            --http-listener "$HTTP_LISTENER_NAME" \
            --rule-type "Basic" \
            --address-pool "$BACKEND_POOL_NAME" \
            --http-settings "$HTTP_SETTINGS_NAME" \
            --priority "$PRIORITY"
    fi
    log_success "Routing rule configured: $ROUTING_RULE_NAME"

    log_info ""
    log_info "┌────────────────────────────────────────────────────────────────────────────────┐"
    log_info "│ STEP 6: Updating Configuration Files                                           │"
    log_info "└────────────────────────────────────────────────────────────────────────────────┘"
    log_info ""
    log_info "  Configuration Update:"
    log_info "    • Backend Pool:        $BACKEND_POOL_NAME → Config"
    log_info "    • Health Probe:        $HEALTH_PROBE_NAME → Config"
    log_info "    • HTTP Settings:       $HTTP_SETTINGS_NAME → Config"
    log_info "    • Routing Rule:        $ROUTING_RULE_NAME → Config"
    log_info ""

    # 6. Update Configuration Files
    log_info "Updating configuration files with routing details..."
    
    # Update tenant configuration file
    update_config "$TENANT_CONFIG_FILE" ".applicationGateway.backendPoolName" "$BACKEND_POOL_NAME"
    update_config "$TENANT_CONFIG_FILE" ".applicationGateway.healthProbeName" "$HEALTH_PROBE_NAME"
    update_config "$TENANT_CONFIG_FILE" ".applicationGateway.httpSettingsName" "$HTTP_SETTINGS_NAME"
    update_config "$TENANT_CONFIG_FILE" ".applicationGateway.httpListenerName" "$HTTP_LISTENER_NAME"
    update_config "$TENANT_CONFIG_FILE" ".applicationGateway.routingRuleName" "$ROUTING_RULE_NAME"

    log_success "========================================================================="
    log_success "Application Gateway Routing Configuration Complete for '$TENANT_NAME'"
    log_success "========================================================================="
    log_info "Configured Components:"
    log_info "  • Backend Pool:      $BACKEND_POOL_NAME → $BACKEND_POOL_FQDN"
    log_info "  • Health Probe:      $HEALTH_PROBE_NAME → $DOMAIN_NAME"
    log_info "  • HTTP Settings:     $HTTP_SETTINGS_NAME"
    log_info "  • HTTPS Listener:    $HTTP_LISTENER_NAME → $DOMAIN_NAME"
    log_info "  • Routing Rule:      $ROUTING_RULE_NAME"
    log_info ""
    log_info "Next Steps:"
    log_info "  • Deploy Container Apps using app-gtwy-apps scripts"
    log_info "  • Test routing: https://$DOMAIN_NAME"
    log_info "========================================================================="
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Execute main function
main "$@"
log_info "You should be able to access the application at https://${DOMAIN_NAME}"
