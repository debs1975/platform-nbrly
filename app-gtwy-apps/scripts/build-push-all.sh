#!/bin/bash

# Build and Push Script for All App Gateway Applications
# Builds Docker images and pushes to Azure Container Registry

set -euo pipefail

# Configuration
ACR_NAME="astradevacr"
ACR_REGISTRY="${ACR_NAME}.azurecr.io"
RESOURCE_GROUP="rg-astrapia-dev"
TAG=${1:-"latest"}

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
    log "Logging in to Azure Container Registry: $ACR_NAME"
    if ! az acr login --name "$ACR_NAME" >/dev/null 2>&1; then
        error "Failed to login to ACR: $ACR_NAME"
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
    log "Starting build and push process for App Gateway applications"
    log "ACR Registry: $ACR_REGISTRY"
    log "Tag: $TAG"
    
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
    echo "Usage: $0 [TAG]"
    echo
    echo "Arguments:"
    echo "  TAG     Docker image tag (default: 'latest')"
    echo
    echo "Examples:"
    echo "  $0              # Build with 'latest' tag"
    echo "  $0 v1.0.0       # Build with 'v1.0.0' tag"
    echo "  $0 dev-$(date +%Y%m%d)  # Build with date-based tag"
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