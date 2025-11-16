#!/bin/bash
set -e

# ============================================================================
# Script: deploy-app.sh
# Purpose: Deploy Container App to Azure Container Apps (without building image)
# Usage: ./deploy-app.sh [environment] <app-name> [image-tag]
# ============================================================================

ENVIRONMENT=${1:-dev}
APP_NAME_PARAM=${2}
CUSTOM_TAG=${3:-}

# Validate required parameter
if [[ -z "$APP_NAME_PARAM" ]]; then
    echo "ERROR: Application name is required"
    echo ""
    echo "Usage: ./deploy-app.sh [environment] <app-name> [image-tag]"
    echo ""
    echo "Arguments:"
    echo "  environment  : Optional - Deployment environment (dev, staging, prod) [default: dev]"
    echo "  app-name     : REQUIRED - Application name (app1 or app2)"
    echo "  image-tag    : Optional - Custom image tag [default: latest]"
    echo ""
    echo "Examples:"
    echo "  ./deploy-app.sh dev app1"
    echo "  ./deploy-app.sh dev app2 v1.2.3"
    echo "  ./deploy-app.sh prod app1 latest"
    exit 1
fi

# Determine config file based on app name
if [ "$APP_NAME_PARAM" = "app2" ]; then
    CONFIG_PREFIX="app2"
elif [ "$APP_NAME_PARAM" = "app1" ]; then
    CONFIG_PREFIX="app1"
else
    echo "ERROR: Invalid app name: $APP_NAME_PARAM"
    echo "Valid options are: app1, app2"
    exit 1
fi

# Load configuration only from sample-app/config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/${CONFIG_PREFIX}-config-${ENVIRONMENT}.json"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../config/infra-config-${ENVIRONMENT}.json"

if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "ERROR: Application configuration file not found: $APP_CONFIG_FILE"
    echo "Usage: ./deploy-app.sh <app-name> [environment] [image-tag]"
    exit 1
fi

if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "ERROR: Infrastructure configuration file not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./deploy-app.sh <app-name> [environment] [image-tag]"
    exit 1
fi

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo "ERROR: 'jq' is required but not installed"
    echo "Install with: brew install jq"
    exit 1
fi

# Extract all variables from unified application config
PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")
LOCATION=$(jq -r '.location' "$INFRA_CONFIG_FILE")
SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$INFRA_CONFIG_FILE")

# Validate required infrastructure parameters
if [ "$SUBSCRIPTION_ID" = "" ] || [ "$SUBSCRIPTION_ID" = "null" ]; then
    echo "ERROR: subscriptionId must be specified in config file"
    echo "Add 'subscriptionId' to the infrastructure section of $APP_CONFIG_FILE"
    exit 1
fi

# Extract container and application configuration
DEFAULT_IMAGE_TAG=$(jq -r '.container.image.tag // "latest"' "$APP_CONFIG_FILE")
IMAGE_NAME=$(jq -r '.container.image.name' "$APP_CONFIG_FILE")
CONTAINER_CPU=$(jq -r '.container.resources.cpu // "0.25"' "$APP_CONFIG_FILE")
CONTAINER_MEMORY=$(jq -r '.container.resources.memory // "0.5Gi"' "$APP_CONFIG_FILE")
CONTAINER_PORT=$(jq -r '.container.port // "8080"' "$APP_CONFIG_FILE")
MIN_REPLICAS=$(jq -r '.scaling.minReplicas // "0"' "$APP_CONFIG_FILE")
MAX_REPLICAS=$(jq -r '.scaling.maxReplicas // "10"' "$APP_CONFIG_FILE")
HTTP_CONCURRENT_REQUESTS=$(jq -r '.scaling.rules.http.concurrentRequests // "10"' "$APP_CONFIG_FILE")
APP_NAME_SUFFIX=$(jq -r '.application.name' "$APP_CONFIG_FILE")

# Use custom tag if provided, otherwise use default from config
IMAGE_TAG=${CUSTOM_TAG:-$DEFAULT_IMAGE_TAG}

# ============================================================================
# Azure Authentication - Use inline authentication
# ============================================================================
echo "Authenticating with Azure..."

# Check if already logged in
if ! az account show &>/dev/null; then
    echo "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Set subscription if specified
if [ -n "$SUBSCRIPTION_ID" ] && [ "$SUBSCRIPTION_ID" != "null" ]; then
    echo "Setting subscription: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Verify subscription
CURRENT_SUB=$(az account show --query id -o tsv)
echo "Using subscription: $CURRENT_SUB"

# Construct resource names (lowercase)
RG_NAME=$(jq -r '.resourceGroup.name' "$INFRA_CONFIG_FILE")
ACR_NAME=$(jq -r '.acr.name' "$INFRA_CONFIG_FILE")
CAE_NAME=$(jq -r '.containerAppsEnvironment.name' "$INFRA_CONFIG_FILE")
APP_NAME="${PROJECT_NAME}-${ENV}-${LOCATION}-${APP_NAME_SUFFIX}-ca"
UAMI_NAME=$(jq -r '.managedIdentity.name' "$INFRA_CONFIG_FILE")
KV_NAME=$(jq -r '.keyVault.name' "$INFRA_CONFIG_FILE")

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
    echo "Please ensure the infrastructure is deployed first"
    exit 1
fi

if ! az acr show --name "$ACR_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "ERROR: Container Registry '${ACR_NAME}' not found"
    echo "Please ensure the container registry is deployed"
    exit 1
fi

if ! az containerapp env show --name "$CAE_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "ERROR: Container Apps Environment '${CAE_NAME}' not found"
    echo "Please ensure the container apps environment is deployed"
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
        --ingress internal \
        --transport http \
        --cpu "$CONTAINER_CPU" \
        --memory "$CONTAINER_MEMORY" \
        --min-replicas "$MIN_REPLICAS" \
        --max-replicas "$MAX_REPLICAS" \
        --env-vars \
            "ENVIRONMENT=${ENV}" \
            "LOG_LEVEL=$(jq -r '.environmentVariables.LOG_LEVEL // "INFO"' "$APP_CONFIG_FILE")" \
            "PORT=${CONTAINER_PORT}" \
            "AZURE_CLIENT_ID=${UAMI_CLIENT_ID}" \
            "DATABASE_URL=secretref:postgres-connection-string" \
            "SECRET_KEY=secretref:api-secret-key" \
        --secrets \
            "postgres-connection-string=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/postgres-connection-string,identityref:$UAMI_ID" \
            "api-secret-key=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/api-secret-key,identityref:$UAMI_ID" \
        --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=${APP_NAME_SUFFIX}"
    
    echo "✓ Container App created successfully"
    echo "ℹ️  Ingress: internal (accessible via environment gateway only)"
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
    echo ""
    echo "⚠️  Note: To enable internal ingress for path-based routing, run:"
    echo "   az containerapp ingress update \\"
    echo "     --name $APP_NAME \\"
    echo "     --resource-group $RG_NAME \\"
    echo "     --type internal \\"
    echo "     --target-port $CONTAINER_PORT \\"
    echo "     --transport http"
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

# Get ingress type
INGRESS_TYPE=$(az containerapp show \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --query "properties.configuration.ingress.external" -o tsv)

if [ "$INGRESS_TYPE" = "false" ]; then
    INGRESS_INFO="Internal (via environment gateway only)"
    CUSTOM_DOMAIN=$(jq -r '.customDomain.domainName // empty' "$INFRA_CONFIG_FILE")
    if [ -n "$CUSTOM_DOMAIN" ]; then
        GATEWAY_URL="https://${CUSTOM_DOMAIN}${ROOT_PATH}"
    else
        GATEWAY_URL="<custom-domain>${ROOT_PATH} (configure custom domain first)"
    fi
else
    INGRESS_INFO="External (direct access)"
    GATEWAY_URL="https://${APP_FQDN}${ROOT_PATH}"
fi

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo "Container App:  ${APP_NAME}"
echo "Image:          ${FULL_IMAGE_NAME}"
echo "Revision:       ${REVISION}"
echo "Ingress:        ${INGRESS_INFO}"
echo ""
echo "Internal URL:   https://${APP_FQDN}"
echo "Gateway URL:    ${GATEWAY_URL}"
echo ""
echo "Test endpoints (via gateway):"
echo "  Health:       ${GATEWAY_URL}/health"
echo "  Readiness:    ${GATEWAY_URL}/health/ready"
echo "  Liveness:     ${GATEWAY_URL}/health/live"
echo "  Info:         ${GATEWAY_URL}/api/info"
echo "  API Docs:     ${GATEWAY_URL}/docs"
if [ "$APP_NAME_PARAM" = "app2" ]; then
    echo "  Tasks:        ${GATEWAY_URL}/api/tasks"
fi
echo ""
echo "ℹ️  Note: For path-based routing to work:"
echo "   1. Deploy routing rules: cd scripts && ./deploy-routing.sh ${ENVIRONMENT}"
echo "   2. Ensure custom domain is assigned: cd ../../iac-cli && ./scripts/06-deploy-ssl.sh ${ENVIRONMENT}"
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
