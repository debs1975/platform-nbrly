#!/bin/bash
set -euo pipefail

# ============================================================================
# Script: deploy-yaml.sh
# Purpose: Build and deploy sample FastAPI app using YAML manifest
# Usage: ./deploy-yaml.sh [environment]
# ============================================================================
# This script deploys the Container App using a YAML manifest instead of
# CLI flags, providing better version control and declarative configuration.
# ============================================================================

ENVIRONMENT=${1:-dev}

# Load infrastructure and application configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../../iac-cli/config/parameters-${ENVIRONMENT}.json"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/app-config-${ENVIRONMENT}.json"
MANIFEST_TEMPLATE="${SCRIPT_DIR}/../manifests/containerapp.yaml"
MANIFEST_OUTPUT="${SCRIPT_DIR}/../manifests/.generated/containerapp-${ENVIRONMENT}.yaml"

echo ""
echo "============================================================"
echo "  Deploy Sample API - YAML-Based Deployment"
echo "============================================================"
echo ""

# Validate configuration file
if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "ERROR: Infrastructure configuration file not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./deploy-yaml.sh [dev|staging|prod]"
    exit 1
fi

# Validate application configuration file
if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "ERROR: Application configuration file not found: $APP_CONFIG_FILE"
    echo "Usage: ./deploy-yaml.sh [dev|staging|prod]"
    exit 1
fi

# Validate manifest template
if [ ! -f "$MANIFEST_TEMPLATE" ]; then
    echo "ERROR: YAML manifest template not found: $MANIFEST_TEMPLATE"
    exit 1
fi

# Check for jq
if ! command -v jq &>/dev/null; then
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
IMAGE_TAG=$(jq -r '.container.image.tag' "$APP_CONFIG_FILE")
CONTAINER_CPU=$(jq -r '.container.resources.cpu' "$APP_CONFIG_FILE")
CONTAINER_MEMORY=$(jq -r '.container.resources.memory' "$APP_CONFIG_FILE")
CONTAINER_PORT=$(jq -r '.container.port' "$APP_CONFIG_FILE")
MIN_REPLICAS=$(jq -r '.scaling.minReplicas' "$APP_CONFIG_FILE")
MAX_REPLICAS=$(jq -r '.scaling.maxReplicas' "$APP_CONFIG_FILE")
HTTP_CONCURRENT_REQUESTS=$(jq -r '.scaling.rules.http.concurrentRequests' "$APP_CONFIG_FILE")
APP_NAME_SUFFIX=$(jq -r '.application.name' "$APP_CONFIG_FILE")

# Extract health probe configuration
LIVENESS_PROBE_PATH=$(jq -r '.healthProbes.liveness.path' "$APP_CONFIG_FILE")
LIVENESS_INITIAL_DELAY=$(jq -r '.healthProbes.liveness.initialDelaySeconds' "$APP_CONFIG_FILE")
LIVENESS_PERIOD=$(jq -r '.healthProbes.liveness.periodSeconds' "$APP_CONFIG_FILE")
LIVENESS_TIMEOUT=$(jq -r '.healthProbes.liveness.timeoutSeconds' "$APP_CONFIG_FILE")
LIVENESS_FAILURE_THRESHOLD=$(jq -r '.healthProbes.liveness.failureThreshold' "$APP_CONFIG_FILE")

READINESS_PROBE_PATH=$(jq -r '.healthProbes.readiness.path' "$APP_CONFIG_FILE")
READINESS_INITIAL_DELAY=$(jq -r '.healthProbes.readiness.initialDelaySeconds' "$APP_CONFIG_FILE")
READINESS_PERIOD=$(jq -r '.healthProbes.readiness.periodSeconds' "$APP_CONFIG_FILE")
READINESS_TIMEOUT=$(jq -r '.healthProbes.readiness.timeoutSeconds' "$APP_CONFIG_FILE")
READINESS_FAILURE_THRESHOLD=$(jq -r '.healthProbes.readiness.failureThreshold' "$APP_CONFIG_FILE")

STARTUP_PROBE_PATH=$(jq -r '.healthProbes.startup.path' "$APP_CONFIG_FILE")
STARTUP_INITIAL_DELAY=$(jq -r '.healthProbes.startup.initialDelaySeconds' "$APP_CONFIG_FILE")
STARTUP_PERIOD=$(jq -r '.healthProbes.startup.periodSeconds' "$APP_CONFIG_FILE")
STARTUP_TIMEOUT=$(jq -r '.healthProbes.startup.timeoutSeconds' "$APP_CONFIG_FILE")
STARTUP_FAILURE_THRESHOLD=$(jq -r '.healthProbes.startup.failureThreshold' "$APP_CONFIG_FILE")

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

# Application configuration
IMAGE_NAME=$(jq -r '.container.image.name' "$APP_CONFIG_FILE")
FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Configuration:"
echo "  Environment: ${ENV}"
echo "  Resource Group: ${RG_NAME}"
echo "  Container App: ${APP_NAME}"
echo "  Image: ${FULL_IMAGE_NAME}"
echo "  Manifest: ${MANIFEST_OUTPUT}"
echo ""

# Verify infrastructure exists
echo "Verifying infrastructure..."

if ! az group show --name "$RG_NAME" &>/dev/null; then
    echo "ERROR: Resource group not found. Run infrastructure deployment scripts first."
    exit 1
fi

if ! az acr show --name "$ACR_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "ERROR: Container Registry not found. Run ./iac-cli/scripts/03-deploy-compute.sh first."
    exit 1
fi

if ! az containerapp env show --name "$CAE_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "ERROR: Container Apps Environment not found. Run ./iac-cli/scripts/03-deploy-compute.sh first."
    exit 1
fi

echo "Infrastructure verified"

# Get Managed Identity details
echo ""
echo "Retrieving managed identity details..."
UAMI_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query id -o tsv)
UAMI_CLIENT_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query clientId -o tsv)

echo "Managed Identity: ${UAMI_NAME}"

# Build Docker image
echo ""
echo "Building Docker image..."
docker build -t "$FULL_IMAGE_NAME" "${SCRIPT_DIR}/.."

echo ""
echo "Logging into Azure Container Registry..."
az acr login --name "$ACR_NAME"

echo ""
echo "Pushing image to ACR..."
docker push "$FULL_IMAGE_NAME"

echo "Image pushed: $FULL_IMAGE_NAME"

# Generate YAML manifest with variable substitution
echo ""
echo "Generating YAML manifest from template..."

# Create output directory
mkdir -p "$(dirname "$MANIFEST_OUTPUT")"

# Create a temporary file for substitution
TEMP_MANIFEST="${MANIFEST_OUTPUT}.tmp"
cp "$MANIFEST_TEMPLATE" "$TEMP_MANIFEST"

# Perform variable substitution using sed
sed -i.bak \
    -e "s|{{APP_NAME}}|${APP_NAME}|g" \
    -e "s|{{CAE_NAME}}|${CAE_NAME}|g" \
    -e "s|{{IMAGE_NAME}}|${FULL_IMAGE_NAME}|g" \
    -e "s|{{UAMI_ID}}|${UAMI_ID}|g" \
    -e "s|{{UAMI_CLIENT_ID}}|${UAMI_CLIENT_ID}|g" \
    -e "s|{{ACR_SERVER}}|${ACR_NAME}.azurecr.io|g" \
    -e "s|{{ENVIRONMENT}}|${ENV}|g" \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{KV_NAME}}|${KV_NAME}|g" \
    -e "s|{{MAX_REPLICAS}}|${MAX_REPLICAS}|g" \
    -e "s|{{MIN_REPLICAS}}|${MIN_REPLICAS}|g" \
    -e "s|{{CONTAINER_CPU}}|${CONTAINER_CPU}|g" \
    -e "s|{{CONTAINER_MEMORY}}|${CONTAINER_MEMORY}|g" \
    -e "s|{{CONTAINER_PORT}}|${CONTAINER_PORT}|g" \
    -e "s|{{HTTP_CONCURRENT_REQUESTS}}|${HTTP_CONCURRENT_REQUESTS}|g" \
    -e "s|{{LIVENESS_PROBE_PATH}}|${LIVENESS_PROBE_PATH}|g" \
    -e "s|{{LIVENESS_INITIAL_DELAY}}|${LIVENESS_INITIAL_DELAY}|g" \
    -e "s|{{LIVENESS_PERIOD}}|${LIVENESS_PERIOD}|g" \
    -e "s|{{LIVENESS_TIMEOUT}}|${LIVENESS_TIMEOUT}|g" \
    -e "s|{{LIVENESS_FAILURE_THRESHOLD}}|${LIVENESS_FAILURE_THRESHOLD}|g" \
    -e "s|{{READINESS_PROBE_PATH}}|${READINESS_PROBE_PATH}|g" \
    -e "s|{{READINESS_INITIAL_DELAY}}|${READINESS_INITIAL_DELAY}|g" \
    -e "s|{{READINESS_PERIOD}}|${READINESS_PERIOD}|g" \
    -e "s|{{READINESS_TIMEOUT}}|${READINESS_TIMEOUT}|g" \
    -e "s|{{READINESS_FAILURE_THRESHOLD}}|${READINESS_FAILURE_THRESHOLD}|g" \
    -e "s|{{STARTUP_PROBE_PATH}}|${STARTUP_PROBE_PATH}|g" \
    -e "s|{{STARTUP_INITIAL_DELAY}}|${STARTUP_INITIAL_DELAY}|g" \
    -e "s|{{STARTUP_PERIOD}}|${STARTUP_PERIOD}|g" \
    -e "s|{{STARTUP_TIMEOUT}}|${STARTUP_TIMEOUT}|g" \
    -e "s|{{STARTUP_FAILURE_THRESHOLD}}|${STARTUP_FAILURE_THRESHOLD}|g" \
    -e "s|{{SUBSCRIPTION_ID}}|${SUBSCRIPTION_ID}|g" \
    -e "s|{{RESOURCE_GROUP}}|${RG_NAME}|g" \
    -e "s|{{CREATED_DATE}}|$(date +%Y-%m-%d)|g" \
    "$TEMP_MANIFEST"

# Move the substituted file to final location
mv "$TEMP_MANIFEST" "$MANIFEST_OUTPUT"
rm -f "${TEMP_MANIFEST}.bak"

echo "Manifest generated: ${MANIFEST_OUTPUT}"

# Check if Container App exists
APP_EXISTS=$(az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG_NAME" \
    --query name -o tsv 2>/dev/null || echo "")

if [ -z "$APP_EXISTS" ]; then
    echo ""
    echo "Creating new Container App from YAML manifest..."
    
    az containerapp create \
        --resource-group "$RG_NAME" \
        --name "$APP_NAME" \
        --yaml "$MANIFEST_OUTPUT"
    
    echo "Container App created"
else
    echo ""
    echo "Updating existing Container App from YAML manifest..."
    
    az containerapp update \
        --name "$APP_NAME" \
        --resource-group "$RG_NAME" \
        --yaml "$MANIFEST_OUTPUT"
    
    echo "Container App updated"
fi

# Get application URL
echo ""
echo "Retrieving application URL..."
APP_FQDN=$(az containerapp show \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --query properties.configuration.ingress.fqdn -o tsv)

echo ""
echo "============================================================"
echo "Deployment Complete!"
echo "============================================================"
echo ""
echo "Container App: ${APP_NAME}"
echo "Image: ${FULL_IMAGE_NAME}"
echo "URL: https://${APP_FQDN}"
echo ""
echo "Test endpoints:"
echo "  Health:     https://${APP_FQDN}/app1/health"
echo "  Readiness:  https://${APP_FQDN}/app1/health/ready"
echo "  Liveness:   https://${APP_FQDN}/app1/health/live"
echo "  Info:       https://${APP_FQDN}/app1/api/info"
echo "  API Docs:   https://${APP_FQDN}/app1/docs"
echo ""
echo "Generated manifest:"
echo "  ${MANIFEST_OUTPUT}"
echo ""
echo "View logs:"
echo "  az containerapp logs show --name ${APP_NAME} --resource-group ${RG_NAME} --follow"
echo ""
echo "View manifest in Azure:"
echo "  az containerapp show --name ${APP_NAME} --resource-group ${RG_NAME} -o yaml"
echo ""
echo "============================================================"
echo ""
