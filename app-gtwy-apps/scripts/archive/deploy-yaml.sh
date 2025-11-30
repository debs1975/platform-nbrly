#!/bin/bash

# Deploy Container Apps using YAML Manifests
# Alternative to the Azure CLI imperative deployment scripts

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resources.resourceGroup.name")
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"
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

# Update YAML manifest with specified image tag and UAMI client IDs
update_manifest_tag() {
    local manifest_file=$1
    local temp_file="${manifest_file}.tmp"
    local tenant=""
    
    # Determine tenant from manifest path
    if [[ "$manifest_file" == *"nbrly"* ]]; then
        tenant="nbrly"
    elif [[ "$manifest_file" == *"bloom"* ]]; then
        tenant="bloom"
    fi
    
    log "Updating image tag to '$TAG' in: $(basename $manifest_file)"
    
    # Get UAMI client ID from infra configuration
    local uami_client_id=""
    if [ -n "$tenant" ]; then
        # Get client ID from managed identity resource (requires querying Azure)
        local uami_resource_id=$(get_infra_value "$ENV" ".resources.tenants.${tenant}.managedIdentity.id")
        local uami_name=$(get_infra_value "$ENV" ".resources.tenants.${tenant}.managedIdentity.name")
        uami_client_id=$(az identity show --ids "$uami_resource_id" --query clientId -o tsv 2>/dev/null || echo "")
        log "Using UAMI Client ID for $tenant: $uami_client_id"
    fi
    
    # Update the image tag and UAMI client ID in the YAML file
    sed -e "s/:latest/:$TAG/g" \
        -e "s/#{NBRLY_UAMI_CLIENT_ID}#/$uami_client_id/g" \
        -e "s/#{BLOOM_UAMI_CLIENT_ID}#/$uami_client_id/g" \
        "$manifest_file" > "$temp_file"
    mv "$temp_file" "$manifest_file"
    
    return 0
}

# Deploy Container App using YAML manifest
deploy_with_yaml() {
    local manifest_file=$1
    local app_name=$(grep "name:" "$manifest_file" | head -1 | awk '{print $2}')
    
    log "Deploying Container App: $app_name using YAML manifest"
    
    # Check if Container App already exists
    if az containerapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Updating existing Container App: $app_name"
        
        # Use update command for existing apps
        if az containerapp update --name "$app_name" --resource-group "$RESOURCE_GROUP" --yaml "$manifest_file" --only-show-errors; then
            success "Successfully updated: $app_name"
            return 0
        else
            error "Failed to update: $app_name"
            return 1
        fi
    else
        log "Creating new Container App: $app_name"
        
        # Use create command for new apps
        if az containerapp create --resource-group "$RESOURCE_GROUP" --yaml "$manifest_file" --only-show-errors; then
            success "Successfully created: $app_name"
            return 0
        else
            error "Failed to create: $app_name"
            return 1
        fi
    fi
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

# Restore original manifest files
restore_manifests() {
    log "Restoring original manifest files..."
    cd "$MANIFESTS_DIR"
    
    # Restore original tags (latest) and placeholders in all manifest files
    find . -name "*.yaml" -type f | while read -r manifest; do
        local tenant=""
        if [[ "$manifest" == *"nbrly"* ]]; then
            tenant="nbrly"
        elif [[ "$manifest" == *"bloom"* ]]; then
            tenant="bloom"
        fi
        
        # Get UAMI client ID from infra configuration
        local uami_client_id=""
        if [ -n "$tenant" ]; then
            local uami_resource_id=$(get_infra_value "$ENV" ".resources.tenants.${tenant}.managedIdentity.id")
            uami_client_id=$(az identity show --ids "$uami_resource_id" --query clientId -o tsv 2>/dev/null || echo "")
        fi
        
        # Restore original values
        sed -i.bak -e "s/:$TAG/:latest/g" \
            -e "s/$uami_client_id/#{${tenant^^}_UAMI_CLIENT_ID}#/g" \
            "$manifest"
        rm -f "${manifest}.bak"
    done
    
    cd - >/dev/null
}

# Main execution
main() {
    log "Starting Container Apps deployment using YAML manifests"
    log "Environment: $ENV"
    log "Resource Group: $RESOURCE_GROUP"
    log "Manifests Directory: $MANIFESTS_DIR"
    log "Image Tag: $TAG"
    
    # Check prerequisites
    check_azure_login
    check_containerapp_extension
    check_jq || exit 1
    
    # Generate manifests from templates
    log "Generating manifests from templates..."
    if ! "$SCRIPT_DIR/helpers/generate-manifests.sh"; then
        error "Failed to generate manifests from templates"
        exit 1
    fi
    
    # Check if manifests directory exists
    if [ ! -d "$MANIFESTS_DIR" ]; then
        error "Manifests directory not found: $MANIFESTS_DIR"
        exit 1
    fi
    
    # Change to manifests directory
    cd "$MANIFESTS_DIR"
    
    # Define manifest files
    declare -a manifests=(
        "nbrly/nbapp1-containerapp.yaml"
        "nbrly/nbapp2-containerapp.yaml"
        "bloom/bmapp1-containerapp.yaml"
        "bloom/bmapp2-containerapp.yaml"
    )
    
    # Always update manifests to replace placeholders with actual UAMI client IDs
    log "Updating UAMI client IDs and image tags in manifest files..."
    for manifest in "${manifests[@]}"; do
        if [ -f "$manifest" ]; then
            update_manifest_tag "$manifest"
        fi
    done
    
    # Deploy each Container App
    local success_count=0
    local total_count=${#manifests[@]}
    declare -A app_fqdns
    
    for manifest in "${manifests[@]}"; do
        if [ ! -f "$manifest" ]; then
            warning "Manifest file not found: $manifest"
            continue
        fi
        
        local app_name=$(grep "name:" "$manifest" | head -1 | awk '{print $2}')
        local tenant_app=$(basename $(dirname "$manifest"))/$(basename "$manifest" -containerapp.yaml)
        
        log "Processing: $tenant_app ($app_name)"
        
        if deploy_with_yaml "$manifest"; then
            ((success_count++))
            app_fqdns["$app_name"]=$(get_app_fqdn "$app_name")
        else
            warning "Failed to deploy: $app_name"
            app_fqdns["$app_name"]="FAILED"
        fi
        
        echo # Empty line for readability
    done
    
    # Always restore original manifest files with placeholders
    restore_manifests
    
    # Return to original directory
    cd - >/dev/null
    
    # Summary
    log "YAML deployment summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All Container Apps deployed successfully using YAML manifests!"
        
        log "Container Apps deployed:"
        for manifest in "${manifests[@]}"; do
            if [ -f "$MANIFESTS_DIR/$manifest" ]; then
                local app_name=$(grep "name:" "$MANIFESTS_DIR/$manifest" | head -1 | awk '{print $2}')
                local fqdn="${app_fqdns[$app_name]}"
                echo "  - $app_name: https://$fqdn"
            fi
        done
        
        log ""
        log "Next steps:"
        log "1. Configure Application Gateway routing: ./08-configure-routing.sh"
        log "2. Test the applications: ./test-routing.sh"
        log "3. Set up custom domains and SSL certificates"
        
        exit 0
    else
        error "Some Container Apps failed to deploy"
        
        log "Failed deployments:"
        for manifest in "${manifests[@]}"; do
            if [ -f "$MANIFESTS_DIR/$manifest" ]; then
                local app_name=$(grep "name:" "$MANIFESTS_DIR/$manifest" | head -1 | awk '{print $2}')
                if [ "${app_fqdns[$app_name]:-}" == "FAILED" ]; then
                    echo "  - $app_name"
                fi
            fi
        done
        
        exit 1
    fi
}

# Help function
show_help() {
    echo "Deploy Container Apps using YAML Manifests"
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
    echo "This script uses declarative YAML manifests instead of imperative Azure CLI commands."
    echo "The YAML files are located in: $MANIFESTS_DIR"
    echo
    echo "Applications deployed:"
    echo "  - ca-nbrly-nbapp1-dev (from nbrly/nbapp1-containerapp.yaml)"
    echo "  - ca-nbrly-nbapp2-dev (from nbrly/nbapp2-containerapp.yaml)"
    echo "  - ca-bloom-bmapp1-dev (from bloom/bmapp1-containerapp.yaml)"
    echo "  - ca-bloom-bmapp2-dev (from bloom/bmapp2-containerapp.yaml)"
    echo
    local acr_name=$(get_infra_value "$ENV" ".resources.containerRegistry.name" 2>/dev/null || echo "<ACR_NAME>")
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - Container Apps extension installed"
    echo "  - Images available in ACR: ${acr_name}.azurecr.io"
    echo "  - Container App Environment: <tenant-specific>"
    echo "  - YAML manifest files in: $MANIFESTS_DIR"
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