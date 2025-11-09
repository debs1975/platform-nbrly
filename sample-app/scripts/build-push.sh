#!/bin/bash
set -e

# ============================================================================
# Script: build-push.sh
# Purpose: Build Docker image and push to Azure Container Registry
# Usage: ./build-push.sh [environment] [tag] [app]
# ============================================================================

ENVIRONMENT=${1:-dev}
CUSTOM_TAG=${2:-}
APP_NAME=${3:-app}

# Determine which app to build
if [ "$APP_NAME" = "app2" ]; then
    CONFIG_PREFIX="app2"
    DOCKERFILE="Dockerfile.app2"
    IMAGE_SUFFIX="app2"
else
    CONFIG_PREFIX="app"
    APP_NAME="app"
    DOCKERFILE="Dockerfile.app1"
    IMAGE_SUFFIX="app1"
fi

# Load infrastructure and application configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../../iac-cli/config/parameters-${ENVIRONMENT}.json"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/${CONFIG_PREFIX}-config-${ENVIRONMENT}.json"

if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "ERROR: Infrastructure configuration file not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./build-push.sh [dev|staging|prod] [custom-tag] [app|app2]"
    exit 1
fi

if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "ERROR: Application configuration file not found: $APP_CONFIG_FILE"
    echo "Usage: ./build-push.sh [dev|staging|prod] [custom-tag] [app|app2]"
    exit 1
fi

# Check for required tools
if ! command -v docker &> /dev/null; then
    echo "ERROR: 'docker' is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "ERROR: 'jq' is required but not installed"
    echo "Install with: brew install jq"
    exit 1
fi

# Extract variables from infrastructure config
PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")

# Extract variables from application config
DEFAULT_IMAGE_TAG=$(jq -r '.container.image.tag' "$APP_CONFIG_FILE")
IMAGE_NAME=$(jq -r '.container.image.name' "$APP_CONFIG_FILE")

# Use custom tag if provided, otherwise use default from config
IMAGE_TAG=${CUSTOM_TAG:-$DEFAULT_IMAGE_TAG}

# ============================================================================
# Azure Authentication
# ============================================================================
source "${SCRIPT_DIR}/../../iac-cli/scripts/helpers/azure-login.sh"
azure_login "$ENV"

# Construct resource names (lowercase)
RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"
ACR_NAME="${PROJECT_NAME}${ENV}eastusacr"

# Full image name
FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=========================================="
echo "Building and Pushing Docker Image"
echo "=========================================="
echo "Application:    ${APP_NAME} (${IMAGE_SUFFIX})"
echo "Dockerfile:     ${DOCKERFILE}"
echo "Environment:    ${ENV}"
echo "ACR:            ${ACR_NAME}"
echo "Image Name:     ${IMAGE_NAME}"
echo "Image Tag:      ${IMAGE_TAG}"
echo "Full Image:     ${FULL_IMAGE_NAME}"
echo "=========================================="

# Verify ACR exists
echo ""
echo "Verifying Azure Container Registry..."

if ! az acr show --name "$ACR_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "ERROR: Container Registry '${ACR_NAME}' not found in resource group '${RG_NAME}'"
    echo "Run infrastructure deployment first: ./iac-cli/scripts/03-deploy-compute.sh ${ENV}"
    exit 1
fi

echo "ACR verified: ${ACR_NAME}"

# Build Docker image
echo ""
echo "Building Docker image..."
echo "Build context: ${SCRIPT_DIR}/.."
echo "Using Dockerfile: ${DOCKERFILE}"

docker build \
    -f "${SCRIPT_DIR}/../${DOCKERFILE}" \
    -t "$FULL_IMAGE_NAME" \
    -t "${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest" \
    --build-arg ENVIRONMENT="${ENV}" \
    "${SCRIPT_DIR}/.."

echo "✓ Image built successfully"

# Login to ACR
echo ""
echo "Logging into Azure Container Registry..."
az acr login --name "$ACR_NAME"

echo "✓ Logged in to ACR"

# Push image to ACR
echo ""
echo "Pushing image to ACR..."
docker push "$FULL_IMAGE_NAME"

# Also push 'latest' tag for the environment
if [ "$IMAGE_TAG" != "latest" ]; then
    echo "Pushing 'latest' tag..."
    docker push "${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest"
fi

echo "✓ Image pushed successfully"

# Get image digest
IMAGE_DIGEST=$(az acr repository show \
    --name "$ACR_NAME" \
    --image "${IMAGE_NAME}:${IMAGE_TAG}" \
    --query digest -o tsv 2>/dev/null || echo "")

echo ""
echo "=========================================="
echo "Build and Push Complete!"
echo "=========================================="
echo "Image:          ${FULL_IMAGE_NAME}"
if [ -n "$IMAGE_DIGEST" ]; then
    echo "Digest:         ${IMAGE_DIGEST}"
fi
echo ""
echo "Available tags for ${IMAGE_NAME}:"
az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_NAME" --output table || echo "  (Could not retrieve tags)"
echo ""
echo "Next steps:"
echo "  1. Deploy to Container Apps:"
echo "     ./scripts/deploy-app.sh ${ENV} ${IMAGE_TAG} ${APP_NAME}"
echo ""
echo "  2. Or deploy with YAML manifest:"
echo "     ./scripts/deploy-yaml.sh ${ENV}"
echo "=========================================="
