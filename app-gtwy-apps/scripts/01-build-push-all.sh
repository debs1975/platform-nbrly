#!/bin/bash

################################################################################
# Build and Push All Container Images to ACR
#
# Builds and pushes both NBRLY and BLOOM tenant applications to Azure Container Registry
#
# USAGE:
#   ./01-build-push-all.sh [TAG]
#
# PARAMETERS:
#   TAG    (Optional) Docker image tag to use. Default: 'latest'
#          Examples: v1.0.0, dev-20251122, latest
#
# EXAMPLES:
#   ./01-build-push-all.sh                # Build with 'latest' tag
#   ./01-build-push-all.sh v1.0.0         # Build with version tag
#   ./01-build-push-all.sh dev-$(date +%Y%m%d)  # Build with date tag
#
# PREREQUISITES:
#   - Azure CLI logged in (az login)
#   - Docker running
#   - ACR access (AcrPush role)
#
# BUILDS:
#   - nbrly-nbapp1:TAG
#   - nbrly-nbapp2:TAG
#   - bloom-bmapp1:TAG
#   - bloom-bmapp2:TAG
################################################################################
#
# ARGUMENTS:
#   ENV     - Environment name (default: 'dev')
#             Used to locate config file: config/infra-${ENV}.json
#   TAG     - Docker image tag (default: 'latest')
#             Applied to all built images
#
# EXAMPLES:
#   ./build-push-all.sh                    # Uses dev env, latest tag
#   ./build-push-all.sh dev v1.0.0         # Uses dev env, v1.0.0 tag
#   ./build-push-all.sh prod v2.0.0        # Uses prod env, v2.0.0 tag
#
# PREREQUISITES:
#   - Azure CLI installed and authenticated (az login)
#   - Docker installed and running
#   - ACR access permissions
#   - Valid infra config file at: ../config/infra-${ENV}.json
#
# WHAT IT DOES:
#   1. Validates Azure CLI login
#   2. Authenticates to ACR
#   3. Builds Docker images for:
#      - nbrly/nbapp1
#      - nbrly/nbapp2
#      - bloom/bmapp1
#      - bloom/bmapp2
#   4. Tags images for ACR
#   5. Pushes images to ACR
#   6. Provides summary of successful/failed builds
#
# EXIT CODES:
#   0 - All images built and pushed successfully
#   1 - One or more images failed to build/push
#
################################################################################

set -euo pipefail

# Configuration
ENV=${1:-"dev"}
TAG=${2:-"latest"}
INFRA_CONFIG="$(dirname "$0")/../config/infra-${ENV}.json"

if [ ! -f "$INFRA_CONFIG" ]; then
    echo "Infra config not found: $INFRA_CONFIG" >&2
    exit 1
fi

ACR_NAME=$(jq -r '.containerRegistry.name' "$INFRA_CONFIG")
ACR_REGISTRY="${ACR_NAME}.azurecr.io"
RESOURCE_GROUP=$(jq -r '.resourceGroup.name' "$INFRA_CONFIG")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if Azure CLI is logged in
check_azure_login() {
    log "Checking Azure CLI login status..."
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure CLI. Please run: az login"
        exit 1
    fi
    success "Azure CLI login verified"
}

# Login to ACR
acr_login() {
    log "Checking Azure Container Registry: $ACR_NAME"
    
    # First check if ACR exists and is accessible
    if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        error "ACR '$ACR_NAME' not found or not accessible in resource group '$RESOURCE_GROUP'"
        error "Please verify:"
        error "  1. ACR name is correct in infra config"
        error "  2. You have access to the resource group"
        error "  3. ACR exists in the specified resource group"
        exit 1
    fi
    
    log "Logging in to Azure Container Registry: $ACR_NAME"
    if ! az acr login --name "$ACR_NAME"; then
        error "Failed to login to ACR: $ACR_NAME"
        error "This could be due to:"
        error "  1. Insufficient permissions (need AcrPush role)"
        error "  2. Network connectivity issues"
        error "  3. Docker not running"
        error "Please check: az acr check-health --name $ACR_NAME"
        exit 1
    fi
    success "Successfully logged in to ACR: $ACR_NAME"
}

# Build and push function
build_and_push() {
    local app_path=$1
    local image_name=$2
    local tenant=$3
    local app=$4
    
    log "Building and pushing: $image_name"
    
    # Navigate to app directory
    cd "$app_path"
    
    # Build Docker image
    log "Building Docker image: $image_name:$TAG"
    if ! docker build -t "$image_name:$TAG" .; then
        error "Failed to build Docker image: $image_name"
        return 1
    fi
    
    # Tag for ACR
    local acr_image="$ACR_REGISTRY/$image_name:$TAG"
    docker tag "$image_name:$TAG" "$acr_image"
    
    # Push to ACR
    log "Pushing to ACR: $acr_image"
    if ! docker push "$acr_image"; then
        error "Failed to push Docker image: $acr_image"
        return 1
    fi
    
    success "Successfully built and pushed: $acr_image"
    
    # Return to original directory
    cd - >/dev/null
    
    return 0
}

# Main execution
main() {
    echo "================================================================================"
    log "BUILD AND PUSH ALL APPLICATIONS"
    echo "================================================================================"
    log "Purpose: Build and push all NBRLY and BLOOM tenant container images to ACR"
    log "ACR Registry: $ACR_REGISTRY"
    log "Environment: $ENV"
    log "Tag: $TAG"
    echo "================================================================================"
    echo
    
    # Check prerequisites
    check_azure_login
    acr_login
    
    # Define applications
    declare -a apps=(
        "nbrly/nbapp1:nbrly-nbapp1:nbrly:nbapp1"
        "nbrly/nbapp2:nbrly-nbapp2:nbrly:nbapp2"
        "bloom/bmapp1:bloom-bmapp1:bloom:bmapp1"
        "bloom/bmapp2:bloom-bmapp2:bloom:bmapp2"
    )
    
    # Build and push each application
    local success_count=0
    local total_count=${#apps[@]}
    
    for app_config in "${apps[@]}"; do
        IFS=':' read -r app_path image_name tenant app <<< "$app_config"
        
        log "Processing: $tenant/$app ($image_name)"
        
        if build_and_push "$app_path" "$image_name" "$tenant" "$app"; then
            ((success_count++))
        else
            warning "Failed to build/push: $image_name"
        fi
        
        echo # Empty line for readability
    done
    
    # Summary
    log "Build and push summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All applications built and pushed successfully!"
        
        log "Images available in ACR:"
        for app_config in "${apps[@]}"; do
            IFS=':' read -r app_path image_name tenant app <<< "$app_config"
            echo "  - $ACR_REGISTRY/$image_name:$TAG"
        done
        
        log "To deploy these images, use the deployment scripts in ../scripts/"
        
        exit 0
    else
        error "Some applications failed to build/push"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Build and Push Script for App Gateway Applications"
    echo
    echo "Usage: $0 [ENV] [TAG]"
    echo
    echo "Arguments:"
    echo "  ENV     Environment (default: 'dev')"
    echo "  TAG     Docker image tag (default: 'latest')"
    echo
    echo "Examples:"
    echo "  $0              # Build with 'dev' env and 'latest' tag"
    echo "  $0 dev v1.0.0   # Build with 'dev' env and 'v1.0.0' tag"
    echo "  $0 prod v2.0.0  # Build with 'prod' env and 'v2.0.0' tag"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - Docker installed and running"
    echo "  - Access to ACR: $ACR_NAME"
    echo
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac