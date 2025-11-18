#!/bin/bash

# Deploy BLOOM tenant apps to Container App Environment
# Usage: ./scripts/deploy-apps-bloom.sh <environment> <image-tag>

set -e

# Source logging from local helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../helpers/logging.sh"
source "${SCRIPT_DIR}/../helpers/azure-login.sh"

# Parameters
ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}
TENANT_NAME="bloom"

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
ACR_NAME=$(jq -r '.common.containerRegistryName' "$CONFIG_FILE")
ACR_SERVER="${ACR_NAME}.azurecr.io"
CAE_NAME=$(jq -r ".tenants.${TENANT_NAME}.containerAppEnvironmentName" "$CONFIG_FILE")
UAMI_ID=$(jq -r ".tenants.${TENANT_NAME}.userAssignedManagedIdentityId" "$CONFIG_FILE")

if [ -z "$RG_NAME" ] || [ -z "$ACR_NAME" ] || [ -z "$CAE_NAME" ]; then
    log_error "Missing configuration values"
    exit 1
fi

log_info "========================================================"
log_info "Deploying BLOOM Tenant Apps"
log_info "========================================================"
log_info "Resource Group: $RG_NAME"
log_info "Container App Environment: $CAE_NAME"
log_info "ACR Server: $ACR_SERVER"

# Login to Azure
azure_login

# Deploy BMAPP1
log_info "Deploying BMAPP1..."
BMAPP1_NAME="${TENANT_NAME}-dev-eastus-bmapp1-ca"
BMAPP1_IMAGE="${ACR_SERVER}/bloom-tenant-bmapp1:${IMAGE_TAG}"

az containerapp create \
    --resource-group "$RG_NAME" \
    --name "$BMAPP1_NAME" \
    --environment "$CAE_NAME" \
    --image "$BMAPP1_IMAGE" \
    --target-port 8000 \
    --ingress internal \
    --cpu 0.5 \
    --memory 1.0Gi \
    --min-replicas 0 \
    --max-replicas 5 \
    --registry-server "$ACR_SERVER" \
    --registry-identity "$UAMI_ID" \
    --env-vars \
        ENVIRONMENT="$ENVIRONMENT" \
        ALLOWED_ORIGINS="*" \
        PORT="8000" \
    --query properties.configuration.ingress.fqdn -o tsv >/dev/null

log_success "BMAPP1 deployed: $BMAPP1_NAME"

# Deploy BMAPP2
log_info "Deploying BMAPP2..."
BMAPP2_NAME="${TENANT_NAME}-dev-eastus-bmapp2-ca"
BMAPP2_IMAGE="${ACR_SERVER}/bloom-tenant-bmapp2:${IMAGE_TAG}"

az containerapp create \
    --resource-group "$RG_NAME" \
    --name "$BMAPP2_NAME" \
    --environment "$CAE_NAME" \
    --image "$BMAPP2_IMAGE" \
    --target-port 8001 \
    --ingress internal \
    --cpu 0.5 \
    --memory 1.0Gi \
    --min-replicas 0 \
    --max-replicas 5 \
    --registry-server "$ACR_SERVER" \
    --registry-identity "$UAMI_ID" \
    --env-vars \
        ENVIRONMENT="$ENVIRONMENT" \
        ALLOWED_ORIGINS="*" \
        PORT="8001" \
    --query properties.configuration.ingress.fqdn -o tsv >/dev/null

log_success "BMAPP2 deployed: $BMAPP2_NAME"

log_info "========================================================"
log_info "BLOOM Tenant Apps Deployment Complete"
log_info "========================================================"
log_info "BMAPP1: $BMAPP1_NAME"
log_info "BMAPP2: $BMAPP2_NAME"
