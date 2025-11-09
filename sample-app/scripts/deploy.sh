#!/bin/bash
set -e

# ============================================================================
# Script: deploy.sh
# Purpose: Build and deploy sample FastAPI app to Azure Container Apps
# Usage: ./deploy.sh [environment]
# ============================================================================

ENVIRONMENT=${1:-dev}

# Load infrastructure configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/parameters-${ENVIRONMENT}.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    echo "Usage: ./deploy.sh [dev|staging|prod]"
    exit 1
fi

# Extract variables from config
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
LOCATION=$(jq -r '.location' "$CONFIG_FILE")
CONTAINER_APPS_MAX_REPLICAS=$(jq -r '.containerAppsMaxReplicas' "$CONFIG_FILE")

# ============================================================================
# Azure Authentication
# ============================================================================
source "${SCRIPT_DIR}/../../scripts/helpers/azure-login.sh"
azure_login "$ENV"

# Construct resource names (lowercase)
RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"
ACR_NAME="${PROJECT_NAME}${ENV}eastusacr"
CAE_NAME="${PROJECT_NAME}-${ENV}-eastus-cae"
APP_NAME="${PROJECT_NAME}-${ENV}-eastus-api-ca"
UAMI_NAME="${PROJECT_NAME}-${ENV}-eastus-uami"
KV_NAME="${PROJECT_NAME}${ENV}eastuskv"

# Application configuration
IMAGE_NAME="sample-api"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=========================================="
echo "Deploying Sample API to Azure Container Apps"
echo "=========================================="
echo "Environment: ${ENV}"
echo "Resource Group: ${RG_NAME}"
echo "Container App: ${APP_NAME}"
echo "Image: ${FULL_IMAGE_NAME}"
echo "=========================================="

# Verify infrastructure exists
echo ""
echo "🔍 Verifying infrastructure..."

if ! az group show --name "$RG_NAME" &>/dev/null; then
    echo "❌ Resource group not found. Run infrastructure deployment scripts first."
    exit 1
fi

if ! az acr show --name "$ACR_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "❌ Container Registry not found. Run ./scripts/03-deploy-compute.sh first."
    exit 1
fi

if ! az containerapp env show --name "$CAE_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "❌ Container Apps Environment not found. Run ./scripts/03-deploy-compute.sh first."
    exit 1
fi

echo "✅ Infrastructure verified"

# Get Managed Identity details
UAMI_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query id -o tsv)
UAMI_CLIENT_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query clientId -o tsv)

echo ""
echo "📦 Building Docker image..."
docker build -t "$FULL_IMAGE_NAME" "${SCRIPT_DIR}/.."

echo ""
echo "🔐 Logging into Azure Container Registry..."
az acr login --name "$ACR_NAME"

echo ""
echo "⬆️  Pushing image to ACR..."
docker push "$FULL_IMAGE_NAME"

echo "✅ Image pushed: $FULL_IMAGE_NAME"

# Check if Container App exists
APP_EXISTS=$(az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG_NAME" \
    --query name -o tsv 2>/dev/null || echo "")

if [ -z "$APP_EXISTS" ]; then
    echo ""
    echo "🆕 Creating new Container App..."
    
    az containerapp create \
        --resource-group "$RG_NAME" \
        --name "$APP_NAME" \
        --environment "$CAE_NAME" \
        --image "$FULL_IMAGE_NAME" \
        --user-assigned "$UAMI_ID" \
        --registry-server "${ACR_NAME}.azurecr.io" \
        --registry-identity "$UAMI_ID" \
        --target-port 8000 \
        --ingress external \
        --cpu 0.5 \
        --memory 1.0Gi \
        --min-replicas 0 \
        --max-replicas "$CONTAINER_APPS_MAX_REPLICAS" \
        --env-vars \
            "ENVIRONMENT=${ENV}" \
            "DATABASE_URL=secretref:postgres-connection-string" \
            "SECRET_KEY=secretref:api-secret-key" \
        --secrets \
            "postgres-connection-string=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/postgres-connection-string,identityref:$UAMI_ID" \
            "api-secret-key=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/api-secret-key,identityref:$UAMI_ID" \
        --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=sample-api"
    
    echo "✅ Container App created"
else
    echo ""
    echo "🔄 Updating existing Container App..."
    
    az containerapp update \
        --name "$APP_NAME" \
        --resource-group "$RG_NAME" \
        --image "$FULL_IMAGE_NAME"
    
    echo "✅ Container App updated"
fi

# Get application URL
APP_FQDN=$(az containerapp show \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --query properties.configuration.ingress.fqdn -o tsv)

echo ""
echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo "Container App: ${APP_NAME}"
echo "Image: ${FULL_IMAGE_NAME}"
echo "URL: https://${APP_FQDN}"
echo ""
echo "Test endpoints:"
echo "  Health:     https://${APP_FQDN}/health"
echo "  Readiness:  https://${APP_FQDN}/health/ready"
echo "  Liveness:   https://${APP_FQDN}/health/live"
echo "  Info:       https://${APP_FQDN}/api/info"
echo "  API Docs:   https://${APP_FQDN}/docs"
echo ""
echo "To view logs:"
echo "  az containerapp logs show --name ${APP_NAME} --resource-group ${RG_NAME} --follow"
echo "=========================================="
