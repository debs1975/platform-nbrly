#!/bin/bash

# Build and push Docker images for all NBRLY tenant apps
# Usage: ./scripts/build-push-nbrly.sh <environment> <image-tag>

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
log_info "Building and Pushing NBRLY Tenant Apps"
log_info "========================================================"
log_info "Environment: $ENVIRONMENT"
log_info "Image Tag: $IMAGE_TAG"
log_info "ACR: $ACR_SERVER"

# Login to Azure Container Registry
log_info "Logging in to ACR: $ACR_SERVER"
az acr login --name "$ACR_NAME"

# Build and push NBAPP1
log_info "Building NBAPP1 image..."
NBAPP1_IMAGE="${ACR_SERVER}/nbrly-tenant-nbapp1:${IMAGE_TAG}"
docker build -f ../Dockerfile.nbapp1 -t "$NBAPP1_IMAGE" ..
log_success "Built: $NBAPP1_IMAGE"

log_info "Pushing NBAPP1 image to ACR..."
docker push "$NBAPP1_IMAGE"
log_success "Pushed: $NBAPP1_IMAGE"

# Build and push NBAPP2
log_info "Building NBAPP2 image..."
NBAPP2_IMAGE="${ACR_SERVER}/nbrly-tenant-nbapp2:${IMAGE_TAG}"
docker build -f ../Dockerfile.nbapp2 -t "$NBAPP2_IMAGE" ..
log_success "Built: $NBAPP2_IMAGE"

log_info "Pushing NBAPP2 image to ACR..."
docker push "$NBAPP2_IMAGE"
log_success "Pushed: $NBAPP2_IMAGE"

log_info "========================================================"
log_info "NBRLY Tenant Apps Build and Push Complete"
log_info "========================================================"
log_info "NBAPP1: $NBAPP1_IMAGE"
log_info "NBAPP2: $NBAPP2_IMAGE"
