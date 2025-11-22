#!/bin/bash

# Configure Application Gateway path-based routing for BLOOM tenant apps
# This script sets up URL path map routing:
# - /bmapp1 -> bmapp1 Container App
# - /bmapp2 -> bmapp2 Container App
# Usage: ./scripts/configure-routing-bloom.sh

set -e

# Source logging from local helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../helpers/logging.sh"
source "${SCRIPT_DIR}/../helpers/azure-login.sh"

TENANT_NAME="bloom"
TENANT_HOSTNAME="bloom-dev.astrapia.io"

# Configuration file - check local first, then fall back to iac-cli
CONFIG_FILE="${SCRIPT_DIR}/../config/.generated/generated-infra-dev.json"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="../../iac-cli/config/.generated/generated-infra-dev.json"
fi

# Validate config file
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Read configuration
RG_NAME=$(jq -r '.common.resourceGroupName' "$CONFIG_FILE")
AGW_NAME=$(jq -r '.common.appGatewayName' "$CONFIG_FILE")
CAE_NAME=$(jq -r ".tenants.${TENANT_NAME}.containerAppEnvironmentName" "$CONFIG_FILE")

if [ -z "$RG_NAME" ] || [ -z "$AGW_NAME" ] || [ -z "$CAE_NAME" ]; then
    log_error "Missing configuration values"
    exit 1
fi

log_info "========================================================"
log_info "Configuring Application Gateway Path-Based Routing"
log_info "Tenant: BLOOM"
log_info "========================================================"
log_info "Resource Group: $RG_NAME"
log_info "Application Gateway: $AGW_NAME"
log_info "Container App Environment: $CAE_NAME"

# Login to Azure
azure_login

# Get Container App Environment FQDN (ingress FQDN)
CAE_FQDN=$(az containerapp env show \
    --resource-group "$RG_NAME" \
    --name "$CAE_NAME" \
    --query properties.defaultDomain -o tsv)

log_info "Container App Environment FQDN: $CAE_FQDN"

# Get private IP of CAE (used as backend pool target)
CAE_IP=$(az containerapp env show \
    --resource-group "$RG_NAME" \
    --name "$CAE_NAME" \
    --query properties.staticIp -o tsv 2>/dev/null || echo "")

if [ -z "$CAE_IP" ]; then
    log_warn "Could not retrieve static IP from CAE, attempting alternative method"
    # Try to get IP from network interface associated with CAE
    CAE_IP=$(az network nic show \
        --resource-group "$RG_NAME" \
        --name "${CAE_NAME}-nic" \
        --query ipConfigurations[0].privateIpAddress -o tsv 2>/dev/null || echo "")
fi

if [ -z "$CAE_IP" ]; then
    log_warn "Could not retrieve CAE IP automatically, using CAE FQDN for backend pool"
    CAE_IP="$CAE_FQDN"
fi

log_info "Container App Environment IP: $CAE_IP"

# Create backend pool for the tenant
BACKEND_POOL_NAME="${TENANT_NAME}-cae-bp"
log_info "Creating backend pool: $BACKEND_POOL_NAME"

if az network application-gateway address-pool show \
    --gateway-name "$AGW_NAME" \
    --resource-group "$RG_NAME" \
    --name "$BACKEND_POOL_NAME" >/dev/null 2>&1; then
    log_info "Backend pool already exists, updating..."
    az network application-gateway address-pool update \
        --gateway-name "$AGW_NAME" \
        --resource-group "$RG_NAME" \
        --name "$BACKEND_POOL_NAME" \
        --servers "$CAE_IP"
else
    log_info "Creating new backend pool..."
    az network application-gateway address-pool create \
        --gateway-name "$AGW_NAME" \
        --resource-group "$RG_NAME" \
        --name "$BACKEND_POOL_NAME" \
        --servers "$CAE_IP"
fi

log_success "Backend pool configured"

# Create URL path map for path-based routing
URL_PATH_MAP_NAME="${TENANT_NAME}-cae-upm"
log_info "Creating URL path map: $URL_PATH_MAP_NAME"

if az network application-gateway url-path-map show \
    --gateway-name "$AGW_NAME" \
    --resource-group "$RG_NAME" \
    --name "$URL_PATH_MAP_NAME" >/dev/null 2>&1; then
    log_info "URL path map already exists"
else
    log_info "Creating new URL path map..."
    az network application-gateway url-path-map create \
        --gateway-name "$AGW_NAME" \
        --resource-group "$RG_NAME" \
        --name "$URL_PATH_MAP_NAME" \
        --paths "/bmapp1/*" "/bmapp2/*" \
        --address-pool "$BACKEND_POOL_NAME" \
        --http-settings "bloom-http"
fi

log_success "URL path map configured"

# Update listener to use path-based routing if not already configured
LISTENER_NAME="bloom-hl"
log_info "Checking listener configuration: $LISTENER_NAME"

# Create HTTP setting with host name header for routing
HTTP_SETTING_NAME="bloom-cae-http"
log_info "Creating HTTP setting: $HTTP_SETTING_NAME"

if az network application-gateway http-setting show \
    --gateway-name "$AGW_NAME" \
    --resource-group "$RG_NAME" \
    --name "$HTTP_SETTING_NAME" >/dev/null 2>&1; then
    log_info "HTTP setting already exists"
else
    az network application-gateway http-setting create \
        --gateway-name "$AGW_NAME" \
        --resource-group "$RG_NAME" \
        --name "$HTTP_SETTING_NAME" \
        --port 80 \
        --protocol Http \
        --host-name "$TENANT_HOSTNAME"
fi

log_info "========================================================"
log_info "Application Gateway Routing Configuration Complete"
log_info "========================================================"
log_info "Backend Pool: $BACKEND_POOL_NAME"
log_info "URL Path Map: $URL_PATH_MAP_NAME"
log_info "HTTP Setting: $HTTP_SETTING_NAME"
log_info ""
log_info "Routes configured:"
log_info "  /bmapp1/* -> BLOOM App1"
log_info "  /bmapp2/* -> BLOOM App2"
log_info ""
log_info "Access via: https://${TENANT_HOSTNAME}/bmapp1"
log_info "Access via: https://${TENANT_HOSTNAME}/bmapp2"
