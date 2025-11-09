#!/bin/bash
set -e

# ============================================================================
# Script: deploy-app.sh
# Purpose: Deploy Container App to Azure Container Apps (without building image)
# Usage: ./deploy-app.sh [environment] [image-tag] [app-name]
# ============================================================================

ENVIRONMENT=${1:-dev}
CUSTOM_TAG=${2:-}
APP_NAME_PARAM=${3:-app}

# Determine config file based on app name
if [ "$APP_NAME_PARAM" = "app2" ]; then
    CONFIG_PREFIX="app2"
else
    CONFIG_PREFIX="app"
    APP_NAME_PARAM="app"
fi

# Load infrastructure and application configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../../iac-cli/config/parameters-${ENVIRONMENT}.json"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/${CONFIG_PREFIX}-config-${ENVIRONMENT}.json"

if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "ERROR: Infrastructure configuration file not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./deploy-app.sh [dev|staging|prod] [image-tag] [app|app2]"
    exit 1
fi

if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "ERROR: Application configuration file not found: $APP_CONFIG_FILE"
    echo "Usage: ./deploy-app.sh [dev|staging|prod] [image-tag] [app|app2]"
    exit 1
fi

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo "ERROR: 'jq' is required but not installed"
    echo "Install with: brew install jq"
    exit 1
fi

# Extract variables from infrastructure config
PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")
LOCATION=$(jq -r '.location' "$INFRA_CONFIG_FILE")
SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$INFRA_CONFIG_FILE")

# Extract variables from application config
DEFAULT_IMAGE_TAG=$(jq -r '.container.image.tag' "$APP_CONFIG_FILE")
IMAGE_NAME=$(jq -r '.container.image.name' "$APP_CONFIG_FILE")
CONTAINER_CPU=$(jq -r '.container.resources.cpu' "$APP_CONFIG_FILE")
CONTAINER_MEMORY=$(jq -r '.container.resources.memory' "$APP_CONFIG_FILE")
CONTAINER_PORT=$(jq -r '.container.port' "$APP_CONFIG_FILE")
MIN_REPLICAS=$(jq -r '.scaling.minReplicas' "$APP_CONFIG_FILE")
MAX_REPLICAS=$(jq -r '.scaling.maxReplicas' "$APP_CONFIG_FILE")
HTTP_CONCURRENT_REQUESTS=$(jq -r '.scaling.rules.http.concurrentRequests' "$APP_CONFIG_FILE")
APP_NAME_SUFFIX=$(jq -r '.application.name' "$APP_CONFIG_FILE")

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
CAE_NAME="${PROJECT_NAME}-${ENV}-eastus-cae"
APP_NAME="${PROJECT_NAME}-${ENV}-eastus-${APP_NAME_SUFFIX}-ca"
UAMI_NAME="${PROJECT_NAME}-${ENV}-eastus-uami"
KV_NAME="${PROJECT_NAME}${ENV}eastuskv"

# Full image name
FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=========================================="
echo "Deploying Container App"
echo "=========================================="
echo "Environment:    ${ENV}"
echo "Resource Group: ${RG_NAME}"
echo "Container App:  ${APP_NAME}"
echo "Image:          ${FULL_IMAGE_NAME}"
echo "CPU:            ${CONTAINER_CPU}"
echo "Memory:         ${CONTAINER_MEMORY}"
echo "Replicas:       ${MIN_REPLICAS} - ${MAX_REPLICAS}"
echo "=========================================="

# Verify infrastructure exists
echo ""
echo "Verifying infrastructure..."

if ! az group show --name "$RG_NAME" &>/dev/null; then
    echo "ERROR: Resource group '${RG_NAME}' not found"
    echo "Run infrastructure deployment: ./iac-cli/scripts/01-deploy-networking.sh ${ENV}"
    exit 1
fi

if ! az acr show --name "$ACR_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "ERROR: Container Registry '${ACR_NAME}' not found"
    echo "Run compute deployment: ./iac-cli/scripts/03-deploy-compute.sh ${ENV}"
    exit 1
fi

if ! az containerapp env show --name "$CAE_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "ERROR: Container Apps Environment '${CAE_NAME}' not found"
    echo "Run compute deployment: ./iac-cli/scripts/03-deploy-compute.sh ${ENV}"
    exit 1
fi

echo "✓ Infrastructure verified"

# Verify image exists in ACR
echo ""
echo "Verifying image exists in ACR..."
if ! az acr repository show --name "$ACR_NAME" --image "${IMAGE_NAME}:${IMAGE_TAG}" &>/dev/null; then
    echo "WARNING: Image '${IMAGE_NAME}:${IMAGE_TAG}' not found in ACR"
    echo ""
    echo "Available tags:"
    az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_NAME" --output table 2>/dev/null || echo "  No images found for repository '${IMAGE_NAME}'"
    echo ""
    echo "Build and push the image first:"
    echo "  ./scripts/build-push.sh ${ENV} ${IMAGE_TAG}"
    exit 1
fi

echo "✓ Image verified in ACR"

# Get Managed Identity details
echo ""
echo "Retrieving Managed Identity details..."
UAMI_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query id -o tsv)
UAMI_CLIENT_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query clientId -o tsv)

echo "✓ Managed Identity: ${UAMI_NAME}"

# Check if Container App exists
echo ""
APP_EXISTS=$(az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG_NAME" \
    --query name -o tsv 2>/dev/null || echo "")

if [ -z "$APP_EXISTS" ]; then
    echo "Creating new Container App..."
    
    az containerapp create \
        --resource-group "$RG_NAME" \
        --name "$APP_NAME" \
        --environment "$CAE_NAME" \
        --image "$FULL_IMAGE_NAME" \
        --user-assigned "$UAMI_ID" \
        --registry-server "${ACR_NAME}.azurecr.io" \
        --registry-identity "$UAMI_ID" \
        --target-port "$CONTAINER_PORT" \
        --ingress external \
        --cpu "$CONTAINER_CPU" \
        --memory "$CONTAINER_MEMORY" \
        --min-replicas "$MIN_REPLICAS" \
        --max-replicas "$MAX_REPLICAS" \
        --env-vars \
            "ENVIRONMENT=${ENV}" \
            "LOG_LEVEL=$(jq -r '.environmentVariables.LOG_LEVEL' "$APP_CONFIG_FILE")" \
            "PORT=${CONTAINER_PORT}" \
            "AZURE_CLIENT_ID=${UAMI_CLIENT_ID}" \
            "DATABASE_URL=secretref:postgres-connection-string" \
            "SECRET_KEY=secretref:api-secret-key" \
        --secrets \
            "postgres-connection-string=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/postgres-connection-string,identityref:$UAMI_ID" \
            "api-secret-key=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/api-secret-key,identityref:$UAMI_ID" \
        --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=${APP_NAME_SUFFIX}"
    
    echo "✓ Container App created successfully"
else
    echo "Updating existing Container App..."
    
    az containerapp update \
        --name "$APP_NAME" \
        --resource-group "$RG_NAME" \
        --image "$FULL_IMAGE_NAME" \
        --cpu "$CONTAINER_CPU" \
        --memory "$CONTAINER_MEMORY" \
        --min-replicas "$MIN_REPLICAS" \
        --max-replicas "$MAX_REPLICAS"
    
    echo "✓ Container App updated successfully"
fi

# Get application URL
echo ""
echo "Retrieving application details..."
APP_FQDN=$(az containerapp show \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --query properties.configuration.ingress.fqdn -o tsv)

REVISION=$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG_NAME" \
    --query "[0].name" -o tsv)

# Determine root path based on app
if [ "$APP_NAME_PARAM" = "app2" ]; then
    ROOT_PATH="/app2"
else
    ROOT_PATH="/app1"
fi

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo "Container App:  ${APP_NAME}"
echo "Image:          ${FULL_IMAGE_NAME}"
echo "Revision:       ${REVISION}"
echo "URL:            https://${APP_FQDN}"
echo ""
echo "Test endpoints:"
echo "  Health:       https://${APP_FQDN}${ROOT_PATH}/health"
echo "  Readiness:    https://${APP_FQDN}${ROOT_PATH}/health/ready"
echo "  Liveness:     https://${APP_FQDN}${ROOT_PATH}/health/live"
echo "  Info:         https://${APP_FQDN}${ROOT_PATH}/api/info"
echo "  API Docs:     https://${APP_FQDN}${ROOT_PATH}/docs"
if [ "$APP_NAME_PARAM" = "app2" ]; then
    echo "  Tasks:        https://${APP_FQDN}${ROOT_PATH}/api/tasks"
fi
echo ""
echo "Management commands:"
echo "  View logs:"
echo "    az containerapp logs show --name ${APP_NAME} -g ${RG_NAME} --follow"
echo ""
echo "  View revisions:"
echo "    az containerapp revision list --name ${APP_NAME} -g ${RG_NAME} --output table"
echo ""
echo "  Scale manually:"
echo "    az containerapp update --name ${APP_NAME} -g ${RG_NAME} --min-replicas 2 --max-replicas 10"
echo "=========================================="
