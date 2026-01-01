#!/bin/bash

# Generate Container App YAML manifests from templates
# Uses configuration files to populate template placeholders

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}
TENANT=${1:-"all"}  # Accept tenant parameter: nbrly, bloom, or all

# Validate environment is explicitly set (prevent accidental use of default)
if [ "${ENV}" = "dev" ] && [ -z "${ENV+x}" ]; then
    echo -e "${YELLOW}WARNING: ENV not explicitly set, defaulting to 'dev'${NC}" >&2
fi

TEMPLATES_DIR="$SCRIPT_DIR/../../manifests/templates"
OUTPUT_DIR="$SCRIPT_DIR/../../manifests/.generated"
BACKUP_DIR="$SCRIPT_DIR/../../manifests/.bak"

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

# Get Azure subscription ID
get_subscription_id() {
    az account show --query id --output tsv 2>/dev/null || echo "{subscription-id}"
}

# Backup existing manifests
backup_manifests() {
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    local backup_subdir="$BACKUP_DIR/$timestamp"
    
    log "Checking for existing manifests to backup..."
    
    # Check if any manifests exist
    local has_manifests=false
    if [ -d "$OUTPUT_DIR" ] && [ -n "$(ls -A "$OUTPUT_DIR"/*.yaml 2>/dev/null)" ]; then
        has_manifests=true
    fi
    
    if [ "$has_manifests" = false ]; then
        log "No existing manifests found, skipping backup"
        return 0
    fi
    
    # Create backup directory
    mkdir -p "$backup_subdir"
    
    # Backup existing manifests
    local backup_count=0
    if [ -d "$OUTPUT_DIR" ]; then
        for manifest in "$OUTPUT_DIR"/*.yaml; do
            if [ -f "$manifest" ]; then
                mkdir -p "$backup_subdir"
                cp "$manifest" "$backup_subdir/"
                ((backup_count++))
                log "  Backed up: $(basename "$manifest")"
            fi
        done
    fi
    
    if [ $backup_count -gt 0 ]; then
        success "Backed up $backup_count manifest(s) to: $backup_subdir"
    fi
    
    return 0
}

# Generate manifest from template
generate_manifest() {
    local tenant=$1
    local app_key=$2
    local template_file=$3
    local output_file=$4
    
    log "Generating manifest for $tenant/$app_key"
    
    # Get configuration values from infra config
    local resource_group=$(get_infra_value "$ENV" ".resourceGroup.name")
    local acr_name=$(get_infra_value "$ENV" ".containerRegistry.name")
    local acr_registry="${acr_name}.azurecr.io"
    local container_app_env=$(get_infra_value "$ENV" ".containerAppEnvironments.${tenant}.name")
    local key_vault_name=$(get_tenant_value "$tenant" "$ENV" ".keyVault.name")
    local subscription_id=$(get_subscription_id)
    
    # Get UAMI configuration from infra config
    local uami_name=$(get_infra_value "$ENV" ".managedIdentities.${tenant}.name")
    local uami_resource_id=$(get_infra_value "$ENV" ".managedIdentities.${tenant}.id")
    # Get client ID from Azure (since it's not in config)
    local uami_client_id=$(az identity show --ids "$uami_resource_id" --query clientId -o tsv 2>/dev/null || echo "")
    
    # Get application configuration
    local app_name=$(get_app_config "$tenant" "$app_key" "$ENV" "name")
    local image_name=$(get_app_config "$tenant" "$app_key" "$ENV" "image")
    # Remove ACR server prefix if present (config has full path, template adds it)
    image_name="${image_name#${acr_registry}/}"
    local root_path=$(get_app_config "$tenant" "$app_key" "$ENV" "rootPath")
    local cpu=$(get_app_config "$tenant" "$app_key" "$ENV" "cpu")
    local memory=$(get_app_config "$tenant" "$app_key" "$ENV" "memory")
    local min_replicas=$(get_app_config "$tenant" "$app_key" "$ENV" "minReplicas")
    local max_replicas=$(get_app_config "$tenant" "$app_key" "$ENV" "maxReplicas")
    
    # Get database secret name if applicable (required for app2)
    local db_secret_name=""
    if [[ "$app_key" == *"app2" ]]; then
        db_secret_name=$(get_tenant_value "$tenant" "$ENV" ".database.connectionStringSecret")
        if [ -z "$db_secret_name" ]; then
            error "Database connection string secret name is required for $app_key but not found in tenant config"
            return 1
        fi
    fi
    
    # Container name (remove registry prefix)
    local container_name="${image_name##*/}"
    
    # App display name
    local app_display_name="${app_name}"
    
    # Read template
    if [ ! -f "$template_file" ]; then
        error "Template file not found: $template_file"
        return 1
    fi
    
    # Generate manifest by replacing placeholders
    local temp_file=$(mktemp)
    
    sed -e "s|#{APP_NAME}#|${app_name}|g" \
        -e "s|#{RESOURCE_GROUP}#|${resource_group}|g" \
        -e "s|#{SUBSCRIPTION_ID}#|${subscription_id}|g" \
        -e "s|#{CONTAINER_APP_ENV}#|${container_app_env}|g" \
        -e "s|#{UAMI_NAME}#|${uami_name}|g" \
        -e "s|#{ACR_REGISTRY}#|${acr_registry}|g" \
        -e "s|#{CONTAINER_NAME}#|${container_name}|g" \
        -e "s|#{IMAGE_NAME}#|${image_name}|g" \
        -e "s|#{IMAGE_TAG}#|latest|g" \
        -e "s|#{ENVIRONMENT}#|${ENV}|g" \
        -e "s|#{ROOT_PATH}#|${root_path}|g" \
        -e "s|#{APP_DISPLAY_NAME}#|${app_display_name}|g" \
        -e "s|#{TENANT}#|${tenant}|g" \
        -e "s|#{APP_TYPE}#|${app_key}|g" \
        -e "s|#{UAMI_CLIENT_ID}#|${uami_client_id}|g" \
        -e "s|#{CPU}#|${cpu}|g" \
        -e "s|#{MEMORY}#|${memory}|g" \
        -e "s|#{MIN_REPLICAS}#|${min_replicas}|g" \
        -e "s|#{MAX_REPLICAS}#|${max_replicas}|g" \
        -e "s|#{KEY_VAULT_NAME}#|${key_vault_name}|g" \
        -e "s|#{DB_SECRET_NAME}#|${db_secret_name}|g" \
        "$template_file" > "$temp_file"
    
    # Create output directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    
    # Move to final location
    mv "$temp_file" "$output_file"
    
    success "Generated: $output_file"
    return 0
}

# Generate all manifests
generate_all_manifests() {
    log "Generating Container App manifests from templates"
    log "Environment: $ENV"
    log "Tenant: $TENANT"
    log "Templates Directory: $TEMPLATES_DIR"
    log "Output Directory: $OUTPUT_DIR"
    
    # Backup existing manifests first
    backup_manifests
    
    local success_count=0
    local total_count=0
    
    # Generate each manifest based on tenant parameter
    # Format: tenant app template_name
    local apps=()
    
    if [ "$TENANT" = "all" ] || [ "$TENANT" = "nbrly" ]; then
        apps+=("nbrly nbapp1 containerapp-basic.yaml.template")
        apps+=("nbrly nbapp2 containerapp-basic.yaml.template")
    fi
    
    if [ "$TENANT" = "all" ] || [ "$TENANT" = "bloom" ]; then
        apps+=("bloom bmapp1 containerapp-basic.yaml.template")
        apps+=("bloom bmapp2 containerapp-basic.yaml.template")
    fi
    
    for app_config in "${apps[@]}"; do
        ((total_count++))
        
        # Split the configuration
        read -r tenant app_key template_name <<< "$app_config"
        
        local template_file="$TEMPLATES_DIR/$template_name"
        local output_file="$OUTPUT_DIR/${tenant}-${app_key}-${ENV}.yaml"
        
        if generate_manifest "$tenant" "$app_key" "$template_file" "$output_file"; then
            ((success_count++))
        else
            warning "Failed to generate manifest for $tenant/$app_key"
        fi
    done
    
    # Summary
    log "Manifest generation summary:"
    log "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        success "All manifests generated successfully!"
        
        log ""
        log "Generated manifests:"
        # List only the manifests that were actually generated
        for app_config in "${apps[@]}"; do
            read -r tenant app_key template_name <<< "$app_config"
            echo "  - manifests/.generated/${tenant}-${app_key}-${ENV}.yaml"
        done
        
        log ""
        log "Next steps:"
        log "1. Review generated manifests"
        if [ "$TENANT" = "all" ]; then
            log "2. Deploy using: cd ../../scripts && ./07-deploy-yaml.sh"
        else
            log "2. Deploy using: cd ../../scripts && ./08-deploy-yaml-${TENANT}.sh latest"
        fi
        
        return 0
    else
        error "Some manifests failed to generate"
        return 1
    fi
}

# Main execution
main() {
    # Check prerequisites
    check_jq || exit 1
    
    # Check if templates directory exists
    if [ ! -d "$TEMPLATES_DIR" ]; then
        error "Templates directory not found: $TEMPLATES_DIR"
        exit 1
    fi
    
    # Generate all manifests
    generate_all_manifests
}

# Help function
show_help() {
    echo "Generate Container App YAML manifests from templates"
    echo
    echo "Usage: $0"
    echo
    echo "This script generates YAML manifests from templates by replacing placeholders"
    echo "with actual values from configuration files."
    echo
    echo "Template used:"
    echo "  - containerapp-basic.yaml.template (includes KeyVault secret references)"
    echo
    echo "Configuration sources:"
    echo "  - config/parameters-dev.json (global configuration)"
    echo "  - config/nbrly/parameters-dev.json (NBRLY tenant)"
    echo "  - config/bloom/parameters-dev.json (BLOOM tenant)"
    echo
    echo "Generated manifests:"
    echo "  - manifests/nbrly/nbapp1-containerapp.yaml"
    echo "  - manifests/nbrly/nbapp2-containerapp.yaml"
    echo "  - manifests/bloom/bmapp1-containerapp.yaml"
    echo "  - manifests/bloom/bmapp2-containerapp.yaml"
    echo
    echo "Prerequisites:"
    echo "  - jq installed"
    echo "  - Configuration files populated"
    echo "  - UAMI client IDs populated (run populate-uami-ids.sh first)"
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
