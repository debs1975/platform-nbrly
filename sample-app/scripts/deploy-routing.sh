#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../../config/parameters-${ENVIRONMENT}.json"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/app-config-${ENVIRONMENT}.json"
ROUTING_TEMPLATE="${SCRIPT_DIR}/../manifests/routing.yaml"
ROUTING_OUTPUT="${SCRIPT_DIR}/../manifests/.generated/routing-${ENVIRONMENT}.yaml"

if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "Infrastructure config not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./deploy-routing.sh [dev|staging|prod]"
    exit 1
fi

if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "App config not found: $APP_CONFIG_FILE"
    exit 1
fi

if [ ! -f "$ROUTING_TEMPLATE" ]; then
    echo "Routing template not found: $ROUTING_TEMPLATE"
    exit 1
fi

PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")
REGION=$(jq -r '.location' "$INFRA_CONFIG_FILE")
APP_NAME_SUFFIX=$(jq -r '.containerApp.nameSuffix' "$APP_CONFIG_FILE")

RG_NAME="${PROJECT_NAME}-${ENV}-${REGION}-rg"
ENV_NAME="${PROJECT_NAME}-${ENV}-${REGION}-env"
ROUTE_CONFIG_NAME="${PROJECT_NAME}-${ENV}-${REGION}-route"
APP_NAME="${PROJECT_NAME}-${ENV}-${REGION}-${APP_NAME_SUFFIX}"

source "${SCRIPT_DIR}/../../scripts/helpers/azure-login.sh"
azure_login "$ENV"

echo "=========================================="
echo "Deploying HTTP Routing Configuration"
echo "=========================================="
echo "Environment: ${ENV}"
echo "Container Apps Env: ${ENV_NAME}"
echo "Route Config Name: ${ROUTE_CONFIG_NAME}"
echo "Resource Group: ${RG_NAME}"
echo "=========================================="

if ! az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "Container Apps Environment not found: $ENV_NAME"
    echo "Deploy infrastructure first: ./scripts/03-deploy-compute.sh ${ENV}"
    exit 1
fi

echo ""
echo "Generating routing configuration..."
mkdir -p "$(dirname "$ROUTING_OUTPUT")"

sed -e "s|{{APP_NAME}}|${APP_NAME}|g" \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{ENV}}|${ENV}|g" \
    "$ROUTING_TEMPLATE" > "$ROUTING_OUTPUT"

echo "Generated: $ROUTING_OUTPUT"

echo ""
echo "Checking existing route configuration..."
EXISTING_ROUTE=$(az containerapp env http-route-config show \
    --http-route-config-name "$ROUTE_CONFIG_NAME" \
    --resource-group "$RG_NAME" \
    --name "$ENV_NAME" \
    --query id -o tsv 2>/dev/null || echo "")

if [ -z "$EXISTING_ROUTE" ]; then
    echo "Creating new HTTP route configuration..."
    
    az containerapp env http-route-config create \
        --http-route-config-name "$ROUTE_CONFIG_NAME" \
        --resource-group "$RG_NAME" \
        --name "$ENV_NAME" \
        --yaml "$ROUTING_OUTPUT"
    
    echo "Route configuration created: $ROUTE_CONFIG_NAME"
else
    echo "Updating existing HTTP route configuration..."
    
    az containerapp env http-route-config update \
        --http-route-config-name "$ROUTE_CONFIG_NAME" \
        --resource-group "$RG_NAME" \
        --name "$ENV_NAME" \
        --yaml "$ROUTING_OUTPUT"
    
    echo "Route configuration updated: $ROUTE_CONFIG_NAME"
fi

ENV_FQDN=$(az containerapp env show \
    --name "$ENV_NAME" \
    --resource-group "$RG_NAME" \
    --query properties.defaultDomain -o tsv)

echo ""
echo "=========================================="
echo "HTTP Routing Configuration Complete!"
echo "=========================================="
echo "Environment FQDN: ${ENV_FQDN}"
echo "Route Config: ${ROUTE_CONFIG_NAME}"
echo ""
echo "Test the routing:"
echo "  curl https://${ENV_FQDN}/app1"
echo "  curl https://${ENV_FQDN}/app1/health"
echo ""
echo "View route configuration:"
echo "  az containerapp env http-route-config show \\"
echo "    --http-route-config-name ${ROUTE_CONFIG_NAME} \\"
echo "    --resource-group ${RG_NAME} \\"
echo "    --name ${ENV_NAME}"
echo "=========================================="
