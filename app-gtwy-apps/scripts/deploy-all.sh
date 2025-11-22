#!/bin/bash

# Deploy All Applications to Azure Container Apps
# Deploys all 4 applications (nbrly and bloom tenants) with proper configuration

set -euo pipefail

# Configuration
RESOURCE_GROUP="rg-astrapia-dev"
LOCATION="East US"
ACR_NAME="astradevacr"
ACR_REGISTRY="${ACR_NAME}.azurecr.io"
CONTAINER_APP_ENV="cae-astrapia-dev"
LOG_ANALYTICS_WORKSPACE="law-astrapia-dev"
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

# Check if Container Apps extension is installed
check_containerapp_extension() {
    log "Checking Container Apps extension..."
    if ! az extension list --query "[?name=='containerapp']" -o tsv >/dev/null 2>&1; then
        log "Installing Container Apps extension..."
        az extension add --name containerapp --only-show-errors
    fi
    success "Container Apps extension ready"
}

# Deploy Container App
deploy_container_app() {
    local app_name=$1
    local image_name=$2
    local tenant=$3
    local app_type=$4
    local root_path=$5
    
    log "Deploying Container App: $app_name"
    
    # Create or update container app
    if az containerapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Updating existing Container App: $app_name"
        
        az containerapp update \
            --name "$app_name" \
            --resource-group "$RESOURCE_GROUP" \
            --image "$ACR_REGISTRY/$image_name:$TAG" \
            --set-env-vars \
                "ENVIRONMENT=dev" \
                "ROOT_PATH=$root_path" \
                "APP_NAME=${tenant^^}-${app_type^^}" \
                "TENANT=$tenant" \
                "APP_TYPE=$app_type" \
            --only-show-errors
    else
        log "Creating new Container App: $app_name"
        
        az containerapp create \
            --name "$app_name" \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$CONTAINER_APP_ENV" \
            --image "$ACR_REGISTRY/$image_name:$TAG" \
            --registry-server "$ACR_REGISTRY" \
            --target-port 8000 \
            --ingress internal \
            --min-replicas 1 \
            --max-replicas 3 \
            --cpu 0.5 \
            --memory 1Gi \
            --env-vars \
                "ENVIRONMENT=dev" \
                "ROOT_PATH=$root_path" \
                "APP_NAME=${tenant^^}-${app_type^^}" \
                "TENANT=$tenant" \
                "APP_TYPE=$app_type" \
            --only-show-errors
    fi
    
    # Configure health probes
    log "Configuring health probes for: $app_name"
    az containerapp update \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --set "properties.configuration.ingress.transport=http" \
        --only-show-errors
    
    success "Successfully deployed: $app_name"
    
    return 0
}

# Get Container App FQDN
get_app_fqdn() {
    local app_name=$1
    az containerapp show \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.configuration.ingress.fqdn" \
        --output tsv 2>/dev/null || echo "N/A"
}

# Main execution
main() {
    log "Starting deployment process for all App Gateway applications"
    log "Resource Group: $RESOURCE_GROUP"
    log "Container App Environment: $CONTAINER_APP_ENV"
    log "ACR Registry: $ACR_REGISTRY"
    log "Tag: $TAG"
    
    # Check prerequisites
    check_azure_login
    check_containerapp_extension
    
    # Define applications with their configuration
    declare -A apps=(
        ["ca-nbrly-nbapp1-dev"]="nbrly-nbapp1:nbrly:nbapp1:/app1"
        ["ca-nbrly-nbapp2-dev"]="nbrly-nbapp2:nbrly:nbapp2:/app2"
        ["ca-bloom-bmapp1-dev"]="bloom-bmapp1:bloom:bmapp1:/app1"
        ["ca-bloom-bmapp2-dev"]="bloom-bmapp2:bloom:bmapp2:/app2"
    )
    
    # Deploy each application
    local success_count=0
    local total_count=${#apps[@]}
    declare -A app_fqdns
    
    for app_name in "${!apps[@]}"; do
        IFS=':' read -r image_name tenant app_type root_path <<< "${apps[$app_name]}"
        
        log "Processing: $app_name ($tenant/$app_type)"
        
        if deploy_container_app "$app_name" "$image_name" "$tenant" "$app_type" "$root_path"; then
            ((success_count++))
            app_fqdns["$app_name"]=$(get_app_fqdn "$app_name")
        else
            warning "Failed to deploy: $app_name"
            app_fqdns["$app_name"]="FAILED"
        fi
        
        echo # Empty line for readability
    done
    
    # Summary
    log "Deployment summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All applications deployed successfully!"
        
        log "Container Apps deployed:"
        for app_name in "${!apps[@]}"; do
            IFS=':' read -r image_name tenant app_type root_path <<< "${apps[$app_name]}"
            echo "  - $app_name: https://${app_fqdns[$app_name]}"
        done
        
        log ""
        log "Next steps:"
        log "1. Configure Application Gateway routing: ./configure-routing.sh"
        log "2. Test the applications: ./test-routing.sh"
        log "3. Set up custom domains and SSL certificates"
        
        exit 0
    else
        error "Some applications failed to deploy"
        
        log "Failed applications:"
        for app_name in "${!apps[@]}"; do
            if [ "${app_fqdns[$app_name]}" == "FAILED" ]; then
                echo "  - $app_name"
            fi
        done
        
        exit 1
    fi
}

# Help function
show_help() {
    echo "Deploy All Applications to Azure Container Apps"
    echo
    echo "Usage: $0 [TAG]"
    echo
    echo "Arguments:"
    echo "  TAG     Docker image tag to deploy (default: 'latest')"
    echo
    echo "Examples:"
    echo "  $0              # Deploy with 'latest' tag"
    echo "  $0 v1.0.0       # Deploy with 'v1.0.0' tag"
    echo "  $0 dev-123      # Deploy with 'dev-123' tag"
    echo
    echo "Applications deployed:"
    echo "  - ca-nbrly-nbapp1-dev (nbrly-nbapp1:TAG)"
    echo "  - ca-nbrly-nbapp2-dev (nbrly-nbapp2:TAG)"
    echo "  - ca-bloom-bmapp1-dev (bloom-bmapp1:TAG)"
    echo "  - ca-bloom-bmapp2-dev (bloom-bmapp2:TAG)"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - Container Apps extension installed"
    echo "  - Images available in ACR: $ACR_REGISTRY"
    echo "  - Container App Environment: $CONTAINER_APP_ENV"
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