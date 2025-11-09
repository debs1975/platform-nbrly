#!/bin/bash
#
# Deploy HTTP Routing Configuration for Azure Container Apps
#
# This script deploys and manages HTTP routing configurations for Azure Container Apps
# environments. It generates routing manifests from templates and applies them to the
# specified environment.
#
# USAGE:
#   ./deploy-routing.sh [ENVIRONMENT]
#
# PARAMETERS:
#   ENVIRONMENT    Target environment (dev|staging|prod). Defaults to 'dev' if not specified.
#
# PREREQUISITES:
#   - Azure CLI installed and configured
#   - jq utility for JSON processing
#   - Infrastructure config file: ../../iac-cli/config/parameters-{ENVIRONMENT}.json
#   - App config file: ../config/app-config-{ENVIRONMENT}.json
#   - Routing template: ../manifests/routing.yaml
#   - Container Apps Environment must be deployed (via 03-deploy-compute.sh)
#   - Azure login helper script: ../../iac-cli/scripts/helpers/azure-login.sh
#
# FUNCTIONALITY:
#   1. Validates all required configuration files exist
#   2. Extracts configuration values from JSON files (project name, environment, region, etc.)
#   3. Constructs Azure resource names using naming convention
#   4. Authenticates to Azure using helper script
#   5. Verifies Container Apps Environment exists
#   6. Generates routing configuration from template using sed substitution
#   7. Creates or updates HTTP route configuration in Azure
#   8. Displays deployment summary with test URLs and management commands
#
# OUTPUTS:
#   - Generated routing manifest: ../manifests/.generated/routing-{ENVIRONMENT}.yaml
#   - Console output with deployment status and test instructions
#
# EXIT CODES:
#   0 - Success
#   1 - Missing configuration files or Container Apps Environment not found
#
# EXAMPLES:
#   ./deploy-routing.sh              # Deploy to dev environment
#   ./deploy-routing.sh staging      # Deploy to staging environment
#   ./deploy-routing.sh prod         # Deploy to production environment
set -e


ENVIRONMENT=${1:-dev}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../../iac-cli/config/parameters-${ENVIRONMENT}.json"
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
ENV_NAME="${PROJECT_NAME}-${ENV}-${REGION}-cae"
ROUTE_CONFIG_NAME="${PROJECT_NAME}-${ENV}-${REGION}-route"
APP_NAME="${PROJECT_NAME}-${ENV}-${REGION}-${APP_NAME_SUFFIX}"

source "${SCRIPT_DIR}/../../iac-cli/scripts/helpers/azure-login.sh"
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
    echo "Deploy infrastructure first: ./iac-cli/scripts/03-deploy-compute.sh ${ENV}"
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
echo "Deploying HTTP route configuration..."

# Try to create or update (Azure will handle if it exists)
az containerapp env http-route-config set \
    --http-route-config-name "$ROUTE_CONFIG_NAME" \
    --resource-group "$RG_NAME" \
    --name "$ENV_NAME" \
    --yaml "$ROUTING_OUTPUT"

echo "Route configuration deployed: $ROUTE_CONFIG_NAME"

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
echo "  App1:"
echo "    curl https://${ENV_FQDN}/app1/health"
echo "    curl https://${ENV_FQDN}/app1/api/info"
echo ""
echo "  App2:"
echo "    curl https://${ENV_FQDN}/app2/health"
echo "    curl https://${ENV_FQDN}/app2/api/tasks"
echo ""
echo "View route configuration:"
echo "  az containerapp env http-route-config show \\"
echo "    --http-route-config-name ${ROUTE_CONFIG_NAME} \\"
echo "    --resource-group ${RG_NAME} \\"
echo "    --name ${ENV_NAME}"
echo "=========================================="
