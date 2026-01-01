#!/bin/bash

# Build and Push Script for BLOOM Tenant Applications
# Builds Docker images for bmapp1 and bmapp2 and pushes to Azure Container Registry
#
# USAGE:
#   ./03-build-push-bloom.sh [ENV] [TAG]
#
# PARAMETERS:
#   ENV - Environment name (default: "dev")
#         Example values: "dev", "stage", "prod"
#   TAG - Docker image tag (default: "latest")
#         Example values: "v1.0.0", "latest", "dev-20240115"
#
# EXAMPLES:
#   ./03-build-push-bloom.sh                 # Uses dev env, latest tag
#   ./03-build-push-bloom.sh dev             # Uses dev env, latest tag
#   ./03-build-push-bloom.sh dev v1.0.0      # Uses dev env, v1.0.0 tag
#   ./03-build-push-bloom.sh stage v2.0.0    # Uses stage env, v2.0.0 tag
#
# PREREQUISITES:
#   - Azure CLI logged in (az login)
#   - Docker daemon running
#   - config/infra-${ENV}.json configured with ACR settings
#   - BLOOM application source code in ../bloom/bmapp1 and ../bloom/bmapp2
#
# BUILDS:
#   - bmapp1 Docker image tagged as <ACR>/bmapp1:<TAG>
#   - bmapp2 Docker image tagged as <ACR>/bmapp2:<TAG>
#   - Pushes both images to Azure Container Registry

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Configuration
ENV=${1:-"dev"}
TAG=${2:-"latest"}
TENANT="bloom"

# Load configuration values
check_jq || exit 1
ACR_NAME=$(get_infra_value "$ENV" ".containerRegistry.name") # Loaded from infra-dev.json
ACR_REGISTRY="${ACR_NAME}.azurecr.io"

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
build_and_push_app() {
    local app=$1
    
    # Get image configuration from config file
    local image_repo=$(get_app_config "$TENANT" "$app" "$ENV" "image")
    local image_name="${image_repo##*/}"  # Extract image name from full path
    local app_path="$SCRIPT_DIR/../$TENANT/$app"
    
    log "Building and pushing BLOOM application: $app"
    
    # Check if app directory exists
    if [ ! -d "$app_path" ]; then
        error "Application directory not found: $app_path"
        return 1
    fi
    
    # Navigate to app directory
    cd "$app_path"
    
    # Build Docker image
    log "Building Docker image: $image_name:$TAG"
    if ! docker build -t "$image_name:$TAG" .; then
        error "Failed to build Docker image: $image_name"
        cd - >/dev/null
        return 1
    fi
    
    # Tag for ACR
    local acr_image="$ACR_REGISTRY/$image_name:$TAG"
    docker tag "$image_name:$TAG" "$acr_image"
    
    # Push to ACR
    log "Pushing to ACR: $acr_image"
    if ! docker push "$acr_image"; then
        error "Failed to push Docker image: $acr_image"
        cd - >/dev/null
        return 1
    fi
    
    success "Successfully built and pushed: $acr_image"
    
    # Return to scripts directory
    cd - >/dev/null
    
    return 0
}

# Main execution
main() {
    echo "================================================================================"
    log "BUILD AND PUSH BLOOM TENANT APPLICATIONS"
    echo "================================================================================"
    log "Script: 03-build-push-bloom.sh"
    log "Purpose: Build and push BLOOM tenant container images (bmapp1, bmapp2) to ACR"
    echo "-------------------------------------------------------------------------------"
    log "Parameters:"
    log "  Environment:      $ENV"
    log "  Tenant:           $TENANT"
    log "  Image Tag:        $TAG"
    echo "-------------------------------------------------------------------------------"
    log "Azure Resources:"
    log "  ACR Registry:     $ACR_REGISTRY"
    echo "================================================================================"
    echo
    
    # Check prerequisites
    check_azure_login
    acr_login
    
    # Get BLOOM applications from configuration
    declare -a bloom_apps
    while IFS= read -r app; do
        bloom_apps+=("$app")
    done < <(get_tenant_applications "$TENANT" "$ENV")
    
    # Build and push each application
    local success_count=0
    local total_count=${#bloom_apps[@]}
    
    for app in "${bloom_apps[@]}"; do
        log "Processing BLOOM application: $app"
        
        if build_and_push_app "$app"; then
            ((success_count++))
        else
            warning "Failed to build/push BLOOM application: $app"
        fi
        
        echo # Empty line for readability
    done
    
    # Summary
    log "BLOOM build and push summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All BLOOM applications built and pushed successfully!"
        
        log "BLOOM images available in ACR:"
        for app in "${bloom_apps[@]}"; do
            echo "  - $ACR_REGISTRY/$TENANT-$app:$TAG"
        done
        
        log "To deploy BLOOM applications, use: ./deploy-bloom.sh"
        
        exit 0
    else
        error "Failed to build and push some BLOOM applications"
        error "Successful: $success_count/$total_count"
        error "Please check the error messages above for details"
        error "Common issues:"
        error "  - Docker daemon not running"
        error "  - Insufficient ACR permissions"
        error "  - Network connectivity issues"
        error "  - Invalid Dockerfile or build context"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Build and Push Script for BLOOM Tenant Applications"
    echo
    echo "Usage: $0 [TAG]"
    echo
    echo "Arguments:"
    echo "  TAG     Docker image tag (default: 'latest')"
    echo
    echo "Examples:"
    echo "  $0              # Build with 'latest' tag"
    echo "  $0 v1.0.0       # Build with 'v1.0.0' tag"
    echo "  $0 bloom-dev    # Build with 'bloom-dev' tag"
    echo
    echo "Applications built:"
    echo "  - bmapp1 (bloom-bmapp1:TAG)"
    echo "  - bmapp2 (bloom-bmapp2:TAG)"
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