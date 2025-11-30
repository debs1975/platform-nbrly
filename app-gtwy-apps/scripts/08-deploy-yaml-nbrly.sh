#!/bin/bash

# Deploy NBRLY Container Apps using YAML Manifests
#
# USAGE:
#   ./08-deploy-yaml-nbrly.sh [TAG]
#
# PARAMETERS:
#   TAG    (Optional) Docker image tag to deploy. Default: 'latest'
#          Updates YAML manifests with this tag before deployment
#
# EXAMPLES:
#   ./08-deploy-yaml-nbrly.sh             # Deploy with 'latest' tag
#   ./08-deploy-yaml-nbrly.sh v1.0.0      # Deploy specific version
#
# PREREQUISITES:
#   - Azure CLI logged in (az login)
#   - Container Apps extension installed
#   - NBRLY YAML manifests generated in manifests/.generated/
#   - NBRLY images available in ACR with specified TAG
#
# WORKFLOW:
#   1. Generates manifests from templates
#   2. Updates UAMI client IDs and image tags
#   3. Deploys nbrly-nbapp1 and nbrly-nbapp2
#   4. Restores original manifest placeholders

set -euo pipefail

# Load helpers - preserve SCRIPT_DIR before config-loader redefines it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT_DIR="$SCRIPT_DIR"  # Preserve for later use
source "$SCRIPT_DIR/helpers/logging.sh"
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}
TENANT="nbrly"
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resourceGroup.name")
MANIFESTS_DIR="$MAIN_SCRIPT_DIR/../manifests/.generated"
TAG=${1:-"latest"}

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
    
    log "Updating image tag to '$TAG' in: $(basename $manifest_file)"
    
    # Get UAMI client ID from infra configuration
    local uami_resource_id=$(get_infra_value "$ENV" ".resources.tenants.${TENANT}.managedIdentity.id")
    local uami_client_id=$(az identity show --ids "$uami_resource_id" --query clientId -o tsv 2>/dev/null || echo "")
    log "Using UAMI Client ID for $TENANT: $uami_client_id"
    
    # Update the image tag and UAMI client ID in the YAML file
    sed -e "s/:latest/:$TAG/g" \
        -e "s/#{NBRLY_UAMI_CLIENT_ID}#/$uami_client_id/g" \
        "$manifest_file" > "$temp_file"
    mv "$temp_file" "$manifest_file"
    
    return 0
}

# Deploy Container App using YAML manifest
deploy_with_yaml() {
    local manifest_file=$1
    local app_name=$2
    
    log "Deploying Container App: $app_name using YAML manifest"
    
    # Check if Container App already exists
    if az containerapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Updating existing Container App: $app_name"
        
        if az containerapp update --name "$app_name" --resource-group "$RESOURCE_GROUP" --yaml "$manifest_file" --only-show-errors; then
            success "Successfully updated: $app_name"
            return 0
        else
            error "Failed to update: $app_name"
            return 1
        fi
    else
        log "Creating new Container App: $app_name"
        
        if az containerapp create --name "$app_name" --resource-group "$RESOURCE_GROUP" --yaml "$manifest_file" --only-show-errors; then
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
    
    local uami_resource_id=$(get_infra_value "$ENV" ".managedIdentities.${TENANT}-dev-uami.id")
    local uami_client_id=$(az identity show --ids "$uami_resource_id" --query clientId -o tsv 2>/dev/null || echo "")
    
    # Convert tenant to uppercase for placeholder
    local tenant_upper=$(echo "$TENANT" | tr '[:lower:]' '[:upper:]')
    
    for manifest in "$MANIFESTS_DIR"/${TENANT}-*.yaml; do
        [ -f "$manifest" ] || continue
        sed -i.bak -e "s/:$TAG/:latest/g" \
            -e "s/$uami_client_id/#{${tenant_upper}_UAMI_CLIENT_ID}#/g" \
            "$manifest"
        rm -f "${manifest}.bak"
    done
}

# Main execution
main() {
    echo "================================================================================"
    log "DEPLOY NBRLY APPS USING YAML MANIFESTS"
    echo "================================================================================"
    log "Purpose: Deploy NBRLY tenant apps using declarative YAML manifests"
    log "Environment: $ENV"
    log "Resource Group: $RESOURCE_GROUP"
    log "Manifests Directory: $MANIFESTS_DIR"
    log "Image Tag: $TAG"
    echo "================================================================================"
    echo
    
    # Check prerequisites
    check_azure_login
    check_containerapp_extension
    check_jq || exit 1
    
    # Check and setup KeyVault secrets if needed
    log "Checking KeyVault secrets..."
    local kv_name=$(get_infra_value "$ENV" ".keyVault.name")
    if ! az keyvault secret show --vault-name "$kv_name" --name "${TENANT}-psql-connection-string" >/dev/null 2>&1; then
        log "Required KeyVault secrets not found, setting up placeholders..."
        if ! "$MAIN_SCRIPT_DIR/helpers/setup-keyvault-secrets.sh"; then
            warning "Failed to setup KeyVault secrets, deployment may fail for apps with database dependencies"
        fi
    fi
    
    # Generate manifests from templates
    log "Generating manifests from templates..."
    if ! "$MAIN_SCRIPT_DIR/helpers/generate-manifests.sh" "$TENANT"; then
        error "Failed to generate manifests from templates"
        exit 1
    fi
    
    # Check if manifests directory exists
    if [ ! -d "$MANIFESTS_DIR" ]; then
        error "Manifests directory not found: $MANIFESTS_DIR"
        exit 1
    fi
    
    # Define NBRLY manifest files
    declare -a manifests=(
        "${MANIFESTS_DIR}/nbrly-nbapp1.yaml"
        "${MANIFESTS_DIR}/nbrly-nbapp2.yaml"
    )
    
    # Update manifests
    log "Updating UAMI client IDs and image tags in manifest files..."
    for manifest in "${manifests[@]}"; do
        if [ -f "$manifest" ]; then
            update_manifest_tag "$manifest"
        fi
    done
    
    # Deploy each Container App
    local success_count=0
    local total_count=${#manifests[@]}
    
    # Store deployment results
    declare -a deployed_apps
    declare -a deployed_fqdns
    
    for manifest in "${manifests[@]}"; do
        if [ ! -f "$manifest" ]; then
            warning "Manifest file not found: $manifest"
            continue
        fi
        
        # Extract app key from filename (e.g., nbrly-nbapp1.yaml -> nbapp1)
        local filename=$(basename "$manifest" .yaml)
        local app_key="${filename#${TENANT}-}"
        local app_name=$(get_app_config "$TENANT" "$app_key" "$ENV" "name")
        
        if deploy_with_yaml "$manifest" "$app_name"; then
            ((success_count++))
            local fqdn=$(get_app_fqdn "$app_name")
            deployed_apps+=("$app_name")
            deployed_fqdns+=("$fqdn")
        else
            warning "Failed to deploy: $app_name"
            deployed_apps+=("$app_name")
            deployed_fqdns+=("FAILED")
        fi
        
        echo
    done
    
    # Restore original manifest files
    restore_manifests
    
    # Summary
    log "YAML deployment summary for NBRLY:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All NBRLY Container Apps deployed successfully!"
        
        log "Container Apps deployed:"
        local idx=0
        for app_name in "${deployed_apps[@]}"; do
            local fqdn="${deployed_fqdns[$idx]}"
            echo "  - $app_name: https://$fqdn"
            ((idx++))
        done
        
        exit 0
    else
        error "Some NBRLY Container Apps failed to deploy"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Deploy NBRLY Container Apps using YAML Manifests"
    echo
    echo "Usage: $0 [TAG]"
    echo
    echo "Arguments:"
    echo "  TAG     Docker image tag to deploy (default: 'latest')"
    echo
    echo "Examples:"
    echo "  $0              # Deploy with 'latest' tag"
    echo "  $0 v1.0.0       # Deploy with 'v1.0.0' tag"
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
