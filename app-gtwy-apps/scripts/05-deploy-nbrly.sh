#!/bin/bash

# Deploy NBRLY Applications to Azure Container Apps
# Deploys nbapp1 and nbapp2 with proper configuration
#
# USAGE:
#   ./05-deploy-nbrly.sh [ENV] [TAG]
#
# PARAMETERS:
#   ENV - Environment name (default: "dev")
#         Example values: "dev", "stage", "prod"
#   TAG - Docker image tag (default: "latest")
#         Example values: "v1.0.0", "latest", "dev-20240115"
#
# EXAMPLES:
#   ./05-deploy-nbrly.sh                     # Uses dev env, latest tag
#   ./05-deploy-nbrly.sh dev                 # Uses dev env, latest tag
#   ./05-deploy-nbrly.sh dev v1.0.0          # Uses dev env, v1.0.0 tag
#   ./05-deploy-nbrly.sh stage v2.0.0        # Uses stage env, v2.0.0 tag
#
# PREREQUISITES:
#   - Azure CLI logged in (az login)
#   - Container images built and pushed to ACR
#   - config/infra-${ENV}.json configured
#   - Azure Container Apps environment exists
#   - NBRLY tenant configuration in config/nbrly/
#
# DEPLOYS:
#   - nbapp1 to Azure Container Apps with NBRLY configuration
#   - nbapp2 to Azure Container Apps with NBRLY configuration
#   - Environment variables and secrets configured
#   - Ingress and scaling settings applied

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Configuration
ENV=${1:-"dev"}
TAG=${2:-"latest"}
TENANT="nbrly"

# Load configuration values
check_jq || exit 1
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resourceGroup.name") # Loaded from infra-dev.json
ACR_NAME=$(get_infra_value "$ENV" ".containerRegistry.name") # Loaded from infra-dev.json
ACR_REGISTRY="${ACR_NAME}.azurecr.io"

# Get container app environment from tenant-specific config
CONTAINER_APP_ENV=$(get_tenant_value "$TENANT" "$ENV" ".containerAppEnvironment.name")

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

# Deploy NBRLY Container App
deploy_nbrly_app() {
    local app_key=$1
    
    # Get app configuration from config file
    local app_name=$(get_app_config "$TENANT" "$app_key" "$ENV" "name")
    local image_repo=$(get_app_config "$TENANT" "$app_key" "$ENV" "image")
    local root_path=$(get_app_config "$TENANT" "$app_key" "$ENV" "rootPath")
    local cpu=$(get_app_config "$TENANT" "$app_key" "$ENV" "cpu")
    local memory=$(get_app_config "$TENANT" "$app_key" "$ENV" "memory")
    local min_replicas=$(get_app_config "$TENANT" "$app_key" "$ENV" "minReplicas")
    local max_replicas=$(get_app_config "$TENANT" "$app_key" "$ENV" "maxReplicas")
    
    # Get managed identity configuration from tenant-specific config
    local uami_name=$(get_tenant_value "$TENANT" "$ENV" ".managedIdentity.name")
    local uami_resource_id=$(get_tenant_value "$TENANT" "$ENV" ".managedIdentity.id")
    
    # Grant ACR pull access to managed identity
    grant_acr_pull_access "$uami_name" "$ACR_NAME"
    
    # Grant KeyVault access if app needs database (app2)
    if [ "$app_key" == "nbapp2" ]; then
        local kv_name=$(get_tenant_value "$TENANT" "$ENV" ".keyVault.name")
        grant_keyvault_access "$uami_name" "$kv_name"
    fi
    
    log "Deploying NBRLY Container App: $app_name"
    log "  - Image: $image_repo:$TAG"
    log "  - Managed Identity: $uami_name"
    log "  - CPU: $cpu, Memory: $memory"
    log "  - Replicas: $min_replicas-$max_replicas"
    
    # Create or update container app
    if az containerapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Updating existing Container App: $app_name"
        
        az containerapp update \
            --name "$app_name" \
            --resource-group "$RESOURCE_GROUP" \
            --image "$image_repo:$TAG" \
            --cpu "$cpu" \
            --memory "$memory" \
            --min-replicas "$min_replicas" \
            --max-replicas "$max_replicas" \
            --set-env-vars \
                "ENVIRONMENT=$ENV" \
                "ROOT_PATH=$root_path" \
                "APP_NAME=$app_name" \
                "TENANT=$TENANT" \
            --only-show-errors
    else
        log "Creating new Container App: $app_name"
        
        # Create container app with managed identity for ACR pull
        az containerapp create \
            --name "$app_name" \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$CONTAINER_APP_ENV" \
            --image "$image_repo:$TAG" \
            --registry-server "$ACR_REGISTRY" \
            --registry-identity "$uami_resource_id" \
            --user-assigned "$uami_resource_id" \
            --transport http \
            --target-port 8000 \
            --ingress external \
            --min-replicas "$min_replicas" \
            --max-replicas "$max_replicas" \
            --cpu "$cpu" \
            --memory "$memory" \
            --env-vars \
                "ENVIRONMENT=$ENV" \
                "ROOT_PATH=$root_path" \
                "APP_NAME=$app_name" \
                "TENANT=$TENANT" \
            --only-show-errors
        
        # Enable Key Vault secrets if needed (for database connections)
        if [ "$app_key" == "nbapp2" ] || [ "$app_key" == "bmapp2" ]; then
            log "Configuring Key Vault secret reference for database connection..."
            local kv_name=$(get_tenant_value "$TENANT" "$ENV" ".keyVault.name")
            local db_secret="${TENANT}-psql-connection-string"
            
            # Add secret reference
            az containerapp secret set \
                --name "$app_name" \
                --resource-group "$RESOURCE_GROUP" \
                --secrets "db-connection-string=keyvaultref:https://${kv_name}.vault.azure.net/secrets/${db_secret},identityref:$uami_resource_id" \
                --only-show-errors || warning "Could not set Key Vault secret reference"
            
            # Update environment variable to use secret
            az containerapp update \
                --name "$app_name" \
                --resource-group "$RESOURCE_GROUP" \
                --set-env-vars "DATABASE_URL=secretref:db-connection-string" \
                --only-show-errors || warning "Could not set DATABASE_URL from secret"
        fi
    fi
    
    success "Successfully deployed NBRLY app: $app_name"
    
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
    echo "================================================================================"
    log "DEPLOY NBRLY TENANT APPLICATIONS"
    echo "================================================================================"
    log "Script: 05-deploy-nbrly.sh"
    log "Purpose: Deploy NBRLY tenant apps (nbapp1, nbapp2) to Azure Container Apps"
    echo "-------------------------------------------------------------------------------"
    log "Parameters:"
    log "  Environment:               $ENV"
    log "  Tenant:                    $TENANT"
    log "  Image Tag:                 $TAG"
    echo "-------------------------------------------------------------------------------"
    log "Azure Resources:"
    log "  Resource Group:            $RESOURCE_GROUP"
    log "  Container App Environment: $CONTAINER_APP_ENV"
    log "  ACR Registry:              $ACR_REGISTRY"
    echo "================================================================================"
    echo
    
    # Check prerequisites
    check_azure_login
    check_containerapp_extension
    
    # Check and setup KeyVault secrets if needed
    log "Checking KeyVault secrets..."
    local kv_name=$(get_tenant_value "$TENANT" "$ENV" ".keyVault.name")
    local uami_name=$(get_tenant_value "$TENANT" "$ENV" ".managedIdentity.name")
    local secrets_missing=false
    
    if ! az keyvault secret show --vault-name "$kv_name" --name "${TENANT}-api-key" >/dev/null 2>&1; then
        secrets_missing=true
    fi
    if ! az keyvault secret show --vault-name "$kv_name" --name "${TENANT}-psql-connection-string" >/dev/null 2>&1; then
        secrets_missing=true
    fi
    
    if [ "$secrets_missing" = true ]; then
        log "Required KeyVault secrets not found, setting up sample secrets..."
        
        # Grant RBAC first
        log "Granting KeyVault access to managed identity..."
        grant_keyvault_access "$uami_name" "$kv_name"
        
        # Create secrets
        if ! ENV="$ENV" TENANT="$TENANT" "$SCRIPT_DIR/helpers/setup-keyvault-secrets.sh"; then
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
    
    # Define NBRLY applications
    local nbrly_apps=("nbapp1" "nbapp2")
    
    # Deploy each NBRLY application
    local success_count=0
    local total_count=${#nbrly_apps[@]}
    local app_fqdns=()
    
    for app_type in "${nbrly_apps[@]}"; do
        local app_name="ca-$TENANT-${app_type}-$ENV"
        
        log "Processing NBRLY application: $app_type"
        
        if deploy_nbrly_app "$app_type"; then
            ((success_count++))
            app_fqdns+=("$(get_app_fqdn "$app_name")")
        else
            warning "Failed to deploy NBRLY application: $app_type"
            app_fqdns+=("FAILED")
        fi
        
        echo # Empty line for readability
    done
    
    # Summary
    log "NBRLY deployment summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All NBRLY applications deployed successfully!"
        
        log "NBRLY Container Apps deployed:"
        for i in "${!nbrly_apps[@]}"; do
            local app_type="${nbrly_apps[$i]}"
            local app_name="ca-$TENANT-${app_type}-$ENV"
            echo "  - $app_name: https://${app_fqdns[$i]}"
        done
        
        log ""
        log "Health check endpoints:"
        for i in "${!nbrly_apps[@]}"; do
            local app_type="${nbrly_apps[$i]}"
            local app_name="ca-$TENANT-${app_type}-$ENV"
            local fqdn="${app_fqdns[$i]}"
            local root_path=$(get_app_config "$TENANT" "$app_type" "$ENV" "rootPath")
            if [ "$fqdn" != "FAILED" ] && [ "$fqdn" != "N/A" ]; then
                echo "  - $app_name health: https://$fqdn/health"
                echo "  - $app_name docs: https://$fqdn${root_path}/docs"
            fi
        done
        
        log ""
        log "Next steps:"
        log "1. Deploy BLOOM applications: ./deploy-bloom.sh"
        log "2. Configure Application Gateway routing"
        log "3. Test NBRLY applications"
        
        exit 0
    else
        error "Failed to deploy some NBRLY applications"
        error "Successful: $success_count/$total_count"
        
        log "Failed NBRLY applications:"
        for i in "${!nbrly_apps[@]}"; do
            local app_type="${nbrly_apps[$i]}"
            local app_name="ca-$TENANT-${app_type}-$ENV"
            if [ "${app_fqdns[$i]}" == "FAILED" ]; then
                echo "  - $app_name ($app_type)"
            fi
        done
        
        error "Please check the error messages above for details"
        error "Common issues:"
        error "  - Container App Environment not found: $CONTAINER_APP_ENV"
        error "  - Insufficient permissions for managed identity"
        error "  - Invalid image name or tag"
        error "  - Network or ACR connectivity issues"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Deploy NBRLY Applications to Azure Container Apps"
    echo
    echo "Usage: $0 [TAG]"
    echo
    echo "Arguments:"
    echo "  TAG     Docker image tag to deploy (default: 'latest')"
    echo
    echo "Examples:"
    echo "  $0              # Deploy with 'latest' tag"
    echo "  $0 v1.0.0       # Deploy with 'v1.0.0' tag"
    echo "  $0 nbrly-dev    # Deploy with 'nbrly-dev' tag"
    echo
    echo "NBRLY Applications deployed:"
    echo "  - ca-nbrly-nbapp1-$ENV (nbrly-nbapp1:TAG) - root_path: /app1"
    echo "  - ca-nbrly-nbapp2-$ENV (nbrly-nbapp2:TAG) - root_path: /app2"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - Container Apps extension installed"
    echo "  - NBRLY images available in ACR: $ACR_REGISTRY"
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