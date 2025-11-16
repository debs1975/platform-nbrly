#!/bin/bash
set -e

# ============================================================================
# Script: build-push.sh
# Purpose: Build Docker image and push to Azure Container Registry
# Usage: ./build-push.sh [environment] <app-name> [tag]
# ============================================================================

ENVIRONMENT=${1:-dev}
APP_NAME=${2}
CUSTOM_TAG=${3:-}

# Validate required parameter
if [[ -z "$APP_NAME" ]]; then
    echo "ERROR: Application name is required"
    echo ""
    echo "Usage: ./build-push.sh [environment] <app-name> [tag]"
    echo ""
    echo "Arguments:"
    echo "  environment  : Optional - Build environment (dev, staging, prod) [default: dev]"
    echo "  app-name     : REQUIRED - Application name (app1 or app2)"
    echo "  tag          : Optional - Custom image tag [default: from config file]"
    echo ""
    echo "Examples:"
    echo "  ./build-push.sh dev app1"
    echo "  ./build-push.sh dev app2 v1.2.3"
    echo "  ./build-push.sh prod app1 latest"
    exit 1
fi

# Determine which app to build
if [ "$APP_NAME" = "app2" ]; then
    CONFIG_PREFIX="app2"
    DOCKERFILE="Dockerfile.app2"
    IMAGE_SUFFIX="app2"
elif [ "$APP_NAME" = "app1" ]; then
    CONFIG_PREFIX="app1"
    DOCKERFILE="Dockerfile.app1"
    IMAGE_SUFFIX="app1"
else
    echo "ERROR: Invalid app name: $APP_NAME"
    echo "Valid options are: app1, app2"
    exit 1
fi

# Load application configuration from sample-app folder only
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/${CONFIG_PREFIX}-config-${ENVIRONMENT}.json"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../config/infra-config-${ENVIRONMENT}.json"

if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "ERROR: Application configuration file not found: $APP_CONFIG_FILE"
    echo "Usage: ./build-push.sh <app-name> [environment] [tag]"
    exit 1
fi

if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "ERROR: Infrastructure configuration file not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./build-push.sh <app-name> [environment] [tag]"
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

# Extract variables from application config
PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")
DEFAULT_IMAGE_TAG=$(jq -r '.container.image.tag' "$APP_CONFIG_FILE")
IMAGE_NAME=$(jq -r '.container.image.name' "$APP_CONFIG_FILE")
ACR_NAME=$(jq -r '.acr.name' "$INFRA_CONFIG_FILE")
RG_NAME=$(jq -r '.resourceGroup.name' "$INFRA_CONFIG_FILE")

# Validate required configuration values
if [ "$PROJECT_NAME" = "null" ] || [ -z "$PROJECT_NAME" ]; then
    echo "ERROR: 'projectName' not found in configuration file: $APP_CONFIG_FILE"
    exit 1
fi

if [ "$ENV" = "null" ] || [ -z "$ENV" ]; then
    echo "ERROR: 'environment' not found in configuration file: $APP_CONFIG_FILE"
    exit 1
fi

if [ "$ACR_NAME" = "null" ] || [ -z "$ACR_NAME" ]; then
    echo "ERROR: 'infrastructure.acr.name' not found in configuration file: $APP_CONFIG_FILE"
    exit 1
fi

if [ "$RG_NAME" = "null" ] || [ -z "$RG_NAME" ]; then
    echo "ERROR: 'infrastructure.resourceGroup.name' not found in configuration file: $APP_CONFIG_FILE"
    exit 1
fi

# Use custom tag if provided, otherwise use default from config
IMAGE_TAG=${CUSTOM_TAG:-$DEFAULT_IMAGE_TAG}

# ============================================================================
# Azure Authentication
# ============================================================================
source "${SCRIPT_DIR}/../../iac-cli/scripts/helpers/azure-login.sh"
azure_login "$ENV"

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
    echo "Ensure infrastructure is deployed and configuration is correct"
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
