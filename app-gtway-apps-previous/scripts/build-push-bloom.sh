#!/bin/bash

# Build and push Docker images for all BLOOM tenant apps
# Usage: ./scripts/build-push-bloom.sh <environment> <image-tag>

set -e

# Source logging from local helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../helpers/logging.sh"
source "${SCRIPT_DIR}/../helpers/azure-login.sh"

# Parameters
ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}

# Configuration file - check local first, then fall back to iac-cli
CONFIG_FILE="${SCRIPT_DIR}/../config/.generated/generated-infra-dev.json"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="../../iac-cli/config/.generated/generated-infra-dev.json"
fi

# Validate config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Read ACR details from state file
ACR_NAME=$(jq -r '.common.containerRegistryName' "$CONFIG_FILE")
ACR_SERVER="${ACR_NAME}.azurecr.io"

if [ -z "$ACR_NAME" ]; then
    log_error "ACR name not found in configuration"
    exit 1
fi

log_info "========================================================"
log_info "Building and Pushing BLOOM Tenant Apps"
log_info "========================================================"
log_info "Environment: $ENVIRONMENT"
log_info "Image Tag: $IMAGE_TAG"
log_info "ACR: $ACR_SERVER"

# Login to Azure Container Registry
log_info "Logging in to ACR: $ACR_SERVER"
az acr login --name "$ACR_NAME"

# Build and push BMAPP1
log_info "Building BMAPP1 image..."
BMAPP1_IMAGE="${ACR_SERVER}/bloom-tenant-bmapp1:${IMAGE_TAG}"
docker build -f ../Dockerfile.bmapp1 -t "$BMAPP1_IMAGE" ..
log_success "Built: $BMAPP1_IMAGE"

log_info "Pushing BMAPP1 image to ACR..."
docker push "$BMAPP1_IMAGE"
log_success "Pushed: $BMAPP1_IMAGE"

# Build and push BMAPP2
log_info "Building BMAPP2 image..."
BMAPP2_IMAGE="${ACR_SERVER}/bloom-tenant-bmapp2:${IMAGE_TAG}"
docker build -f ../Dockerfile.bmapp2 -t "$BMAPP2_IMAGE" ..
log_success "Built: $BMAPP2_IMAGE"

log_info "Pushing BMAPP2 image to ACR..."
docker push "$BMAPP2_IMAGE"
log_success "Pushed: $BMAPP2_IMAGE"

log_info "========================================================"
log_info "BLOOM Tenant Apps Build and Push Complete"
log_info "========================================================"
log_info "BMAPP1: $BMAPP1_IMAGE"
log_info "BMAPP2: $BMAPP2_IMAGE"
