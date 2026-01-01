#!/bin/bash

# Deploy NBRLY Container Apps using YAML Manifests
#
# USAGE:
#   ./08-deploy-yaml-nbrly.sh [ENV] [TAG]
#
# PARAMETERS:
#   ENV    (Optional) Environment name. Default: 'dev'
#   TAG    (Optional) Docker image tag to deploy. Default: 'latest'
#          Updates YAML manifests with this tag before deployment
#
# EXAMPLES:
#   ./08-deploy-yaml-nbrly.sh                  # Deploy dev env with 'latest' tag
#   ./08-deploy-yaml-nbrly.sh dev v1.0.0       # Deploy dev env with specific version
#   ./08-deploy-yaml-nbrly.sh stage v2.0.0     # Deploy stage env with specific version
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
ENV=${1:-"dev"}
TAG=${2:-"latest"}
TENANT="nbrly"
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resourceGroup.name")
ACR_NAME=$(get_infra_value "$ENV" ".containerRegistry.name")
MANIFESTS_DIR="$MAIN_SCRIPT_DIR/../manifests/.generated"

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

# Grant KeyVault RBAC permissions to managed identity
grant_keyvault_access() {
    local uami_name=$1
    local kv_name=$2
    
    log "Granting KeyVault access to managed identity: $uami_name"
    
    # Get managed identity principal ID
    local uami_principal_id=$(az identity show \
        --name "$uami_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)
    
    if [ -z "$uami_principal_id" ]; then
        error "Failed to get principal ID for managed identity: $uami_name"
        return 1
    fi
    
    # Get KeyVault resource ID
    local kv_id=$(az keyvault show --name "$kv_name" --query id -o tsv)
    
    # Check if role assignment already exists
    local existing_role=$(az role assignment list \
        --assignee "$uami_principal_id" \
        --scope "$kv_id" \
        --role "Key Vault Secrets User" \
        --query "[].id" -o tsv)
    
    if [ -n "$existing_role" ]; then
        log "Role assignment already exists for $uami_name"
    else
        log "Creating 'Key Vault Secrets User' role assignment..."
        az role assignment create \
            --role "Key Vault Secrets User" \
            --assignee-object-id "$uami_principal_id" \
            --assignee-principal-type ServicePrincipal \
            --scope "$kv_id" \
            --output none 2>/dev/null || warning "Role assignment may already exist"
        
        success "✓ KeyVault access granted to $uami_name"
    fi
}

# Grant ACR pull access to managed identity
grant_acr_pull_access() {
    local uami_name=$1
    local acr_name=$2
    
    log "Granting ACR pull access to managed identity: $uami_name"
    
    # Get managed identity principal ID
    local uami_principal_id=$(az identity show \
        --name "$uami_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)
    
    if [ -z "$uami_principal_id" ]; then
        error "Failed to get principal ID for managed identity: $uami_name"
        return 1
    fi
    
    # Get ACR resource ID
    local acr_id=$(az acr show --name "$acr_name" --query id -o tsv)
    
    # Check if role assignment already exists
    local existing_role=$(az role assignment list \
        --assignee "$uami_principal_id" \
        --scope "$acr_id" \
        --role "AcrPull" \
        --query "[].id" -o tsv)
    
    if [ -n "$existing_role" ]; then
        log "AcrPull role assignment already exists for $uami_name"
    else
        log "Creating 'AcrPull' role assignment..."
        az role assignment create \
            --role "AcrPull" \
            --assignee-object-id "$uami_principal_id" \
            --assignee-principal-type ServicePrincipal \
            --scope "$acr_id" \
            --output none 2>/dev/null || warning "Role assignment may already exist"
        
        log "Waiting 15 seconds for RBAC propagation..."
        sleep 15
        
        success "✓ ACR pull access granted to $uami_name"
    fi
}

# Update YAML manifest with specified image tag
update_manifest_tag() {
    local manifest_file=$1
    local temp_file="${manifest_file}.tmp"
    
    log "Updating image tag to '$TAG' in: $(basename $manifest_file)"
    
    # Update only the image tag (UAMI client ID already set during manifest generation)
    sed "s/:latest/:$TAG/g" "$manifest_file" > "$temp_file"
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
        log "Container App exists. Deleting to ensure clean deployment..."
        
        if ! az containerapp delete --name "$app_name" --resource-group "$RESOURCE_GROUP" --yes --only-show-errors; then
            error "Failed to delete existing app: $app_name"
            return 1
        fi
        
        log "Waiting 10 seconds for deletion to complete..."
        sleep 10
    fi
    
    log "Creating Container App: $app_name"
    
    if az containerapp create --name "$app_name" --resource-group "$RESOURCE_GROUP" --yaml "$manifest_file" --only-show-errors; then
        success "Successfully deployed: $app_name"
        return 0
    else
        error "Failed to create: $app_name"
        return 1
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
    
    # Only restore image tag (UAMI client ID is already in correct state from generation)
    for manifest in "$MANIFESTS_DIR"/${TENANT}-*.yaml; do
        [ -f "$manifest" ] || continue
        sed -i.bak "s/:$TAG/:latest/g" "$manifest"
        rm -f "${manifest}.bak"
    done
}

# Main execution
main() {
    echo "================================================================================"
    log "DEPLOY NBRLY APPS USING YAML MANIFESTS"
    echo "================================================================================"
    log "Script: 08-deploy-yaml-nbrly.sh"
    log "Purpose: Deploy NBRLY tenant apps using declarative YAML manifests"
    echo "-------------------------------------------------------------------------------"
    log "Parameters:"
    log "  Environment:         $ENV"
    log "  Tenant:              $TENANT"
    log "  Image Tag:           $TAG"
    echo "-------------------------------------------------------------------------------"
    log "Azure Resources:"
    log "  Resource Group:      $RESOURCE_GROUP"
    log "  Manifests Directory: $MANIFESTS_DIR"
    echo "================================================================================"
    echo
    
    # Check prerequisites
    check_azure_login
    check_containerapp_extension
    check_jq || exit 1
    
    # Grant KeyVault access to managed identity BEFORE generating manifests
    echo "================================================================================"
    log "STEP 1: GRANT KEYVAULT ACCESS TO MANAGED IDENTITY"
    echo "================================================================================"
    local uami_name=$(get_infra_value "$ENV" ".managedIdentities.${TENANT}.name")
    local kv_name=$(get_tenant_value "$TENANT" "$ENV" ".keyVault.name")
    grant_keyvault_access "$uami_name" "$kv_name"
    echo
    
    # Check and setup KeyVault secrets if needed
    log "Checking KeyVault secrets..."
    local secrets_missing=false
    if ! az keyvault secret show --vault-name "$kv_name" --name "${TENANT}-api-key" >/dev/null 2>&1; then
        secrets_missing=true
    fi
    if ! az keyvault secret show --vault-name "$kv_name" --name "${TENANT}-psql-connection-string" >/dev/null 2>&1; then
        secrets_missing=true
    fi
    
    if [ "$secrets_missing" = true ]; then
        log "Required KeyVault secrets not found, setting up sample secrets..."
        if ! ENV="$ENV" "$MAIN_SCRIPT_DIR/helpers/setup-keyvault-secrets.sh"; then
            error "Failed to setup KeyVault secrets, cannot proceed with deployment"
            exit 1
        fi
        success "KeyVault secrets created successfully"
        
        # Wait for RBAC propagation
        log "Waiting 15 seconds for RBAC propagation..."
        sleep 15
        
        # Verify secrets are accessible
        log "Verifying secrets are accessible..."
        if ! az keyvault secret show --vault-name "$kv_name" --name "${TENANT}-api-key" >/dev/null 2>&1; then
            error "Failed to verify secret access for ${TENANT}-api-key"
            error "RBAC may not have propagated yet. Please wait a few minutes and try again."
            exit 1
        fi
        success "Secrets verified and accessible"
    else
        success "KeyVault secrets already configured"
    fi
    echo
    
    # Grant ACR pull access to managed identity
    echo "================================================================================"
    log "STEP 1.5: GRANT ACR PULL ACCESS"
    echo "================================================================================"
    grant_acr_pull_access "$uami_name" "$ACR_NAME"
    echo
    
    # Generate manifests from templates
    echo "================================================================================"
    log "STEP 2: GENERATE MANIFESTS FROM TEMPLATES"
    echo "================================================================================"
    log "Generating YAML manifests for $TENANT tenant..."
    log "Manifests will include UAMI client ID automatically"
    if ! ENV="$ENV" "$MAIN_SCRIPT_DIR/helpers/generate-manifests.sh" "$TENANT"; then
        error "Failed to generate manifests from templates"
        exit 1
    fi
    success "Manifests generated successfully"
    echo
    
    # Check if manifests directory exists
    if [ ! -d "$MANIFESTS_DIR" ]; then
        error "Manifests directory not found: $MANIFESTS_DIR"
        exit 1
    fi
    
    # Define NBRLY manifest files
    declare -a manifests=(
        "${MANIFESTS_DIR}/nbrly-nbapp1-${ENV}.yaml"
        "${MANIFESTS_DIR}/nbrly-nbapp2-${ENV}.yaml"
    )
    
    # Update manifests with image tag
    echo "================================================================================"
    log "STEP 3: UPDATE IMAGE TAGS"
    echo "================================================================================"
    log "Updating manifest files with image tag: $TAG"
    echo
    for manifest in "${manifests[@]}"; do
        if [ -f "$manifest" ]; then
            update_manifest_tag "$manifest"
        fi
    done
    success "All manifests updated successfully"
    echo
    
    # Deploy each Container App
    echo "================================================================================"
    log "STEP 4: DEPLOY NBRLY CONTAINER APPS"
    echo "================================================================================"
    log "Deploying ${#manifests[@]} Container Apps using YAML manifests..."
    echo
    
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
        
        # Extract app key from filename (e.g., nbrly-nbapp1-dev.yaml -> nbapp1)
        local filename=$(basename "$manifest" .yaml)
        # Remove tenant prefix and environment suffix
        local app_key="${filename#${TENANT}-}"  # removes nbrly-
        app_key="${app_key%-${ENV}}"            # removes -dev
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
    echo "================================================================================"
    log "STEP 5: RESTORE ORIGINAL MANIFEST PLACEHOLDERS"
    echo "================================================================================"
    restore_manifests
    success "Manifests restored to original state"
    echo
    
    # Summary
    echo "================================================================================"
    log "DEPLOYMENT SUMMARY"
    echo "================================================================================"
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
        error "Failed to deploy some NBRLY Container Apps"
        error "Successful: $success_count/$total_count"
        error "Please check the error messages above for details"
        error "Common issues:"
        error "  - Invalid YAML manifest syntax"
        error "  - Missing or incorrect UAMI client ID"
        error "  - Container App Environment not accessible"
        error "  - Images not available in ACR with tag: $TAG"
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
