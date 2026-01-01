#!/bin/bash

# Example Script: Deploy Custom Application Using Configuration
# This script demonstrates how to use the config-loader.sh helper
# to read configuration values for deployment automation

set -euo pipefail

# Load configuration helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-loader.sh"

# Configuration
ENV="${1:-dev}"
TENANT="${2:-nbrly}"
APP="${3:-nbapp1}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Main function
main() {
    log "Loading configuration for environment: $ENV, tenant: $TENANT, app: $APP"
    
    # Check if jq is available
    check_jq || exit 1
    
    # Load global configuration values
    log "Reading global configuration..."
    RESOURCE_GROUP=$(get_infra_value "$ENV" ".resourceGroup.name")
    REGION=$(get_infra_value "$ENV" ".location")
    ACR_NAME=$(get_infra_value "$ENV" ".containerRegistry.name")
    AGW_NAME=$(get_infra_value "$ENV" ".applicationGateway.name")
    
    echo "Global Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Region: $REGION"
    echo "  ACR: $ACR_NAME"
    echo "  Application Gateway: $AGW_NAME"
    echo
    
    # Load tenant configuration values
    log "Reading tenant configuration for: $TENANT"
    TENANT_DOMAIN=$(get_tenant_value "$TENANT" "$ENV" ".domain") # Domain from tenant config
    CAE_NAME=$(get_tenant_value "$TENANT" "$ENV" ".containerAppEnvironment")
    CAE_SUBNET=$(get_tenant_value "$TENANT" "$ENV" ".caeSubnetPrefix")
    
    echo "Tenant Configuration ($TENANT):"
    echo "  Domain: $TENANT_DOMAIN"
    echo "  Container App Environment: $CAE_NAME"
    echo "  Subnet: $CAE_SUBNET"
    echo
    
    # Load application-specific configuration
    log "Reading application configuration for: $APP"
    APP_NAME=$(get_app_config "$TENANT" "$APP" "$ENV" "name")
    APP_IMAGE=$(get_app_config "$TENANT" "$APP" "$ENV" "image")
    APP_TAG=$(get_app_config "$TENANT" "$APP" "$ENV" "tag")
    APP_PORT=$(get_app_config "$TENANT" "$APP" "$ENV" "port")
    APP_ROOT_PATH=$(get_app_config "$TENANT" "$APP" "$ENV" "rootPath")
    APP_CPU=$(get_app_config "$TENANT" "$APP" "$ENV" "cpu")
    APP_MEMORY=$(get_app_config "$TENANT" "$APP" "$ENV" "memory")
    APP_MIN_REPLICAS=$(get_app_config "$TENANT" "$APP" "$ENV" "minReplicas")
    APP_MAX_REPLICAS=$(get_app_config "$TENANT" "$APP" "$ENV" "maxReplicas")
    
    echo "Application Configuration ($APP):"
    echo "  Name: $APP_NAME"
    echo "  Image: $APP_IMAGE:$APP_TAG"
    echo "  Port: $APP_PORT"
    echo "  Root Path: $APP_ROOT_PATH"
    echo "  CPU: $APP_CPU"
    echo "  Memory: $APP_MEMORY"
    echo "  Replicas: $APP_MIN_REPLICAS - $APP_MAX_REPLICAS"
    echo
    
    # List all applications for the tenant
    log "All applications for tenant: $TENANT"
    while IFS= read -r app; do
        app_name=$(get_app_config "$TENANT" "$app" "$ENV" "name")
        echo "  - $app: $app_name"
    done < <(get_tenant_applications "$TENANT" "$ENV")
    echo
    
    # Example: Use configuration to construct Azure CLI command
    log "Example Azure CLI command to create Container App:"
    cat << EOF
az containerapp create \\
  --name "$APP_NAME" \\
  --resource-group "$RESOURCE_GROUP" \\
  --environment "$CAE_NAME" \\
  --image "$APP_IMAGE:$APP_TAG" \\
  --target-port $APP_PORT \\
  --ingress internal \\
  --cpu $APP_CPU \\
  --memory $APP_MEMORY \\
  --min-replicas $APP_MIN_REPLICAS \\
  --max-replicas $APP_MAX_REPLICAS \\
  --env-vars \\
    "APP_NAME=$APP_NAME" \\
    "ROOT_PATH=$APP_ROOT_PATH" \\
    "ENVIRONMENT=$ENV"
EOF
    echo
    
    success "Configuration loaded successfully!"
    
    # Example: Export configuration as environment variables
    log "You can also export configuration as environment variables:"
    echo "  source ./config-loader.sh export-global $ENV"
    echo "  source ./config-loader.sh export-tenant $TENANT $ENV"
}

# Show help
show_help() {
    cat << EOF
Example Script: Deploy Custom Application Using Configuration

Usage: $0 [ENV] [TENANT] [APP]

Arguments:
  ENV     Environment (default: dev)
  TENANT  Tenant name (default: nbrly)
  APP     Application name (default: nbapp1)

Examples:
  $0                    # Use defaults (dev, nbrly, nbapp1)
  $0 dev bloom bmapp1   # BLOOM tenant, app1
  $0 staging nbrly nbapp2

Available Functions from config-loader.sh:
  get_global_value <env> <json_path>
  get_tenant_value <tenant> <env> <json_path>
  get_app_config <tenant> <app> <env> <property>
  get_tenant_applications <tenant> <env>
  export_global_config <env>
  export_tenant_config <tenant> <env>

EOF
}

# Handle arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main
        ;;
esac
