#!/bin/bash
set -euo pipefail

# Configuration
ACR_REGISTRY_URL="${ACR_REGISTRY_URL:-your-acr-name.azurecr.io}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
RESOURCE_GROUP="${RESOURCE_GROUP:-your-resource-group}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"

# Container App Environment names per tenant
declare -A CA_ENVIRONMENTS=(
    [nbrly]="ca-env-nbrly-${ENVIRONMENT}"
    [bloom]="ca-env-bloom-${ENVIRONMENT}"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Starting Container Apps deployment${NC}"

# Set subscription if provided
if [ -n "$SUBSCRIPTION_ID" ]; then
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Validate resource group exists
if ! az group exists --name "$RESOURCE_GROUP" | grep -q true; then
    echo -e "${RED}Resource group $RESOURCE_GROUP does not exist${NC}"
    exit 1
fi

# Deploy apps for each tenant
deploy_app() {
    local TENANT=$1
    local APP_NUMBER=$2
    local APP_NAME="${TENANT}app${APP_NUMBER}"
    local CA_ENV_NAME="${CA_ENVIRONMENTS[$TENANT]}"
    local IMAGE_URL="${ACR_REGISTRY_URL}/${APP_NAME}:${IMAGE_TAG}"
    local APP_ROUTE="/app${APP_NUMBER}"
    
    echo -e "${BLUE}Deploying $APP_NAME to $CA_ENV_NAME...${NC}"
    
    # Check if container app environment exists
    if ! az containerapp env show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CA_ENV_NAME" &>/dev/null; then
        echo -e "${RED}Container App Environment $CA_ENV_NAME does not exist${NC}"
        return 1
    fi
    
    # Check if container app already exists
    if az containerapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" &>/dev/null; then
        
        echo -e "${BLUE}Updating existing container app $APP_NAME...${NC}"
        az containerapp update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APP_NAME" \
            --image "$IMAGE_URL" || {
            echo -e "${RED}Failed to update container app $APP_NAME${NC}"
            return 1
        }
    else
        echo -e "${BLUE}Creating new container app $APP_NAME...${NC}"
        az containerapp create \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$CA_ENV_NAME" \
            --name "$APP_NAME" \
            --image "$IMAGE_URL" \
            --target-port 8000 \
            --ingress internal \
            --registry-server "$ACR_REGISTRY_URL" \
            --cpu 0.5 \
            --memory 1.0Gi \
            --min-replicas 1 \
            --max-replicas 3 \
            --env-vars ENVIRONMENT="$ENVIRONMENT" TENANT="$TENANT" \
            --enable-dapr false || {
            echo -e "${RED}Failed to create container app $APP_NAME${NC}"
            return 1
        }
    fi
    
    # Configure ingress route
    echo -e "${BLUE}Configuring ingress route for $APP_NAME...${NC}"
    az containerapp ingress traffic set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --traffic-weight latest=100 || {
        echo -e "${YELLOW}Warning: Failed to configure traffic for $APP_NAME${NC}"
    }
    
    echo -e "${GREEN}Successfully deployed $APP_NAME${NC}"
}

# Deploy all apps
for TENANT in "nbrly" "bloom"; do
    for APP_NUM in 1 2; do
        deploy_app "$TENANT" "$APP_NUM" || {
            echo -e "${RED}Deployment failed for ${TENANT}app${APP_NUM}${NC}"
            exit 1
        }
    done
done

echo -e "${GREEN}All container apps successfully deployed${NC}"
