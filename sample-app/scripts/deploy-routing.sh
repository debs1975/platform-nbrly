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
#   - Infrastructure config file: ../config/infra-config-{ENVIRONMENT}.json
#   - Routing template: ../manifests/routing.yaml
#   - Container Apps Environment must be deployed
#   - Azure login with appropriate permissions
#
# FUNCTIONALITY:
#   1. Validates all required configuration files exist within sample-app
#   2. Extracts configuration values from infrastructure config (project name, environment, region, etc.)
#   3. Constructs Azure resource names using naming convention
#   4. Authenticates to Azure using managed identity or service principal
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
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../config/infra-config-${ENVIRONMENT}.json"
ROUTING_TEMPLATE="${SCRIPT_DIR}/../manifests/routing.yaml"
ROUTING_OUTPUT="${SCRIPT_DIR}/../manifests/.generated/routing-${ENVIRONMENT}.yaml"

# Validate infrastructure configuration file
if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "Infrastructure config not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./deploy-routing.sh [dev|staging|prod]"
    exit 1
fi

# Validate routing template
if [ ! -f "$ROUTING_TEMPLATE" ]; then
    echo "Routing template not found: $ROUTING_TEMPLATE"
    exit 1
fi

# Extract configuration values from config files
PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")
REGION=$(jq -r '.location' "$INFRA_CONFIG_FILE")
SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$INFRA_CONFIG_FILE")
DOMAIN_NAME=$(jq -r '.customDomain.domainName' "$INFRA_CONFIG_FILE")
CERTIFICATE_NAME=$(jq -r '.customDomain.certificateName' "$INFRA_CONFIG_FILE")

# Validate required values
if [ -z "$PROJECT_NAME" ] || [ "$PROJECT_NAME" = "null" ]; then
    echo "ERROR: projectName not found in infrastructure configuration file"
    exit 1
fi

# Construct resource names using naming convention
RG_NAME=$(jq -r '.resourceGroup.name' "$INFRA_CONFIG_FILE")
ENV_NAME=$(jq -r '.containerAppsEnvironment.name' "$INFRA_CONFIG_FILE")
ROUTE_CONFIG_NAME="${PROJECT_NAME}-${ENV}-${REGION}-route"

# Azure authentication
echo "Authenticating to Azure..."
if [ -n "$SUBSCRIPTION_ID" ] && [ "$SUBSCRIPTION_ID" != "null" ]; then
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Verify Azure CLI is logged in
if ! az account show &>/dev/null; then
    echo "ERROR: Not logged into Azure. Please run 'az login'"
    exit 1
fi

echo "=========================================="
echo "Deploying HTTP Routing Configuration"
echo "=========================================="
echo "Environment: ${ENV}"
echo "Project: ${PROJECT_NAME}"
echo "Region: ${REGION}"
echo "Container Apps Env: ${ENV_NAME}"
echo "Route Config Name: ${ROUTE_CONFIG_NAME}"
echo "Resource Group: ${RG_NAME}"
echo "Domain Name: ${DOMAIN_NAME}"
echo "Certificate Name: ${CERTIFICATE_NAME}"
echo "=========================================="

# Verify Container Apps Environment exists
if ! az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "ERROR: Container Apps Environment not found: $ENV_NAME"
    echo "Please deploy the Container Apps Environment first"
    exit 1
fi

# Retrieve certificate ID from the Container Apps Environment
echo ""
echo "Retrieving certificate ID..."
CERTIFICATE_ID=$(az containerapp env certificate list \
    --name "$ENV_NAME" \
    --resource-group "$RG_NAME" \
    --query "[?name=='${CERTIFICATE_NAME}'].id | [0]" \
    -o tsv)

if [ -z "$CERTIFICATE_ID" ] || [ "$CERTIFICATE_ID" = "null" ]; then
    echo "ERROR: Certificate '${CERTIFICATE_NAME}' not found in Container Apps Environment"
    echo "Please upload the certificate first using the SSL deployment script"
    exit 1
fi

echo "Certificate ID: ${CERTIFICATE_ID}"

echo ""
echo "Generating routing configuration..."
mkdir -p "$(dirname "$ROUTING_OUTPUT")"

# Generate routing configuration from template
sed -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{ENV}}|${ENV}|g" \
    -e "s|{{REGION}}|${REGION}|g" \
    -e "s|{{DOMAIN_NAME}}|${DOMAIN_NAME}|g" \
    -e "s|{{CERTIFICATE_ID}}|${CERTIFICATE_ID}|g" \
    "$ROUTING_TEMPLATE" > "$ROUTING_OUTPUT"

echo "Generated: $ROUTING_OUTPUT"

echo ""
echo "Deploying HTTP route configuration..."

# Check if route config exists
ROUTE_EXISTS=$(az containerapp env http-route-config show \
    --http-route-config-name "$ROUTE_CONFIG_NAME" \
    --resource-group "$RG_NAME" \
    --name "$ENV_NAME" 2>/dev/null || echo "")

# Deploy or update HTTP route configuration
if [ -z "$ROUTE_EXISTS" ]; then
    echo "Creating new route configuration..."
    az containerapp env http-route-config create \
        --http-route-config-name "$ROUTE_CONFIG_NAME" \
        --resource-group "$RG_NAME" \
        --name "$ENV_NAME" \
        --yaml "$ROUTING_OUTPUT"
else
    echo "Updating existing route configuration..."
    az containerapp env http-route-config update \
        --http-route-config-name "$ROUTE_CONFIG_NAME" \
        --resource-group "$RG_NAME" \
        --name "$ENV_NAME" \
        --yaml "$ROUTING_OUTPUT"
fi

echo "Route configuration deployed: $ROUTE_CONFIG_NAME"

# Get environment FQDN
ENV_FQDN=$(az containerapp env show \
    --name "$ENV_NAME" \
    --resource-group "$RG_NAME" \
    --query properties.defaultDomain -o tsv)

echo ""
echo "=========================================="
echo "HTTP Routing Configuration Complete!"
echo "=========================================="
echo "Environment FQDN: ${ENV_FQDN}"
echo "Custom Domain: ${DOMAIN_NAME}"
echo "Route Config: ${ROUTE_CONFIG_NAME}"
echo "Certificate: ${CERTIFICATE_NAME}"
echo ""
echo "Test the routing (default domain):"
echo "  App1:"
echo "    curl https://${ENV_FQDN}/app1/health"
echo "    curl https://${ENV_FQDN}/app1/api/info"
echo ""
echo "  App2:"
echo "    curl https://${ENV_FQDN}/app2/health"
echo "    curl https://${ENV_FQDN}/app2/api/tasks"
echo ""
echo "Test the routing (custom domain):"
echo "  App1:"
echo "    curl https://${DOMAIN_NAME}/app1/health"
echo "    curl https://${DOMAIN_NAME}/app1/api/info"
echo ""
echo "  App2:"
echo "    curl https://${DOMAIN_NAME}/app2/health"
echo "    curl https://${DOMAIN_NAME}/app2/api/tasks"
echo ""
echo "View route configuration:"
echo "  az containerapp env http-route-config show \\"
echo "    --http-route-config-name ${ROUTE_CONFIG_NAME} \\"
echo "    --resource-group ${RG_NAME} \\"
echo "    --name ${ENV_NAME}"
echo "=========================================="
