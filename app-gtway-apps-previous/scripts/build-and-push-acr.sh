#!/bin/bash
set -euo pipefail

# Configuration - Update these values
ACR_REGISTRY_NAME="${ACR_REGISTRY_NAME:-your-acr-name}"
ACR_REGISTRY_URL="${ACR_REGISTRY_URL:-your-acr-name.azurecr.io}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

# Tenant and app configurations
declare -a TENANTS=("nbrly" "bloom")
declare -a APPS=("app1" "app2")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting ACR build and push process${NC}"

# Validate ACR registry
if [ -z "$ACR_REGISTRY_URL" ]; then
    echo -e "${RED}Error: ACR_REGISTRY_URL is not set${NC}"
    exit 1
fi

# Login to ACR using managed identity
echo -e "${BLUE}Logging into ACR...${NC}"
az acr login --name "$ACR_REGISTRY_NAME" || {
    echo -e "${RED}Failed to login to ACR. Ensure az CLI is authenticated.${NC}"
    exit 1
}

# Build and push images for each tenant and app
for TENANT in "${TENANTS[@]}"; do
    for APP in "${APPS[@]}"; do
        APP_NAME="${TENANT}${APP}"
        DOCKERFILE_PATH="./app-gtway-apps/${TENANT}/${APP_NAME}/Dockerfile"
        IMAGE_NAME="${ACR_REGISTRY_URL}/${APP_NAME}:${IMAGE_TAG}"
        
        if [ ! -f "$DOCKERFILE_PATH" ]; then
            echo -e "${RED}Dockerfile not found at $DOCKERFILE_PATH${NC}"
            continue
        fi
        
        echo -e "${BLUE}Building Docker image for $APP_NAME...${NC}"
        docker build \
            --build-arg ENVIRONMENT="$ENVIRONMENT" \
            -t "$IMAGE_NAME" \
            -f "$DOCKERFILE_PATH" \
            "./app-gtway-apps/${TENANT}/${APP_NAME}" || {
            echo -e "${RED}Failed to build Docker image for $APP_NAME${NC}"
            exit 1
        }
        
        echo -e "${BLUE}Pushing image to ACR: $IMAGE_NAME${NC}"
        docker push "$IMAGE_NAME" || {
            echo -e "${RED}Failed to push image to ACR${NC}"
            exit 1
        }
        
        echo -e "${GREEN}Successfully pushed $IMAGE_NAME${NC}"
    done
done

echo -e "${GREEN}All images successfully built and pushed to ACR${NC}"
