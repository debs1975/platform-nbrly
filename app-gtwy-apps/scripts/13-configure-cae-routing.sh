#!/bin/bash

# Configure Container App Environment HTTP Routing
# Adds or updates routing rules for individual Container Apps
# Supports appending new routes to existing routing configurations
#
# USAGE:
#   ./13-configure-cae-routing.sh ENV CAE_NAME CONTAINER_APP_NAME ROOT_PATH
#
# PARAMETERS:
#   ENV                  Environment name (dev, stage, prod)
#   CAE_NAME             Container App Environment name (e.g., nbrly-dev-cae, bloom-dev-cae)
#   CONTAINER_APP_NAME   Container App name (e.g., ca-nbrly-nbapp1-dev, ca-bloom-bmapp2-dev)
#   ROOT_PATH            Root path for the app (e.g., /app1, /app2)
#
# EXAMPLES:
#   ./13-configure-cae-routing.sh dev nbrly-dev-cae ca-nbrly-nbapp1-dev /app1
#   ./13-configure-cae-routing.sh dev bloom-dev-cae ca-bloom-bmapp2-dev /app2
#   ./13-configure-cae-routing.sh stage nbrly-stage-cae ca-nbrly-nbapp1-stage /app1
#
# PREREQUISITES:
#   - Azure CLI logged in (az login)
#   - Container Apps Environment deployed
#   - Container App deployed and running
#
# BEHAVIOR:
#   - Generates/updates routing YAML: manifests/.generated/routing/{cae-name}-routing.yaml
#   - If routing file exists, appends new route (if not already present)
#   - If routing file doesn't exist, creates new file with route
#   - Applies routing configuration using: az containerapp env http-route-config create/update

set -euo pipefail

# Load helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/helpers/logging.sh"
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Parse arguments
if [ $# -lt 4 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 ENV CAE_NAME CONTAINER_APP_NAME ROOT_PATH"
    echo "Example: $0 dev nbrly-dev-cae ca-nbrly-nbapp1-dev /app1"
    exit 1
fi

ENV=$1
CAE_NAME=$2
CONTAINER_APP_NAME=$3
ROOT_PATH=$4

# Paths
OUTPUT_DIR="$MAIN_SCRIPT_DIR/../manifests/.generated/routing"

# Load configuration values
check_jq || exit 1
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resourceGroup.name")

# Extract tenant from CAE name (e.g., nbrly-dev-cae -> nbrly)
TENANT=$(echo "$CAE_NAME" | sed -E 's/^([^-]+)-.*/\1/')
TENANT_UPPER=$(echo "$TENANT" | tr '[:lower:]' '[:upper:]')

# Route config name is same as CAE name
ROUTE_CONFIG_NAME="$CAE_NAME"

# Output file based on CAE name
ROUTING_FILE="$OUTPUT_DIR/${CAE_NAME}-routing.yaml"

# Check if Azure CLI is logged in
check_azure_login() {
    log "Checking Azure CLI login status..."
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure CLI. Please run: az login"
        exit 1
    fi
    success "Azure CLI login verified"
}

# Check if route already exists in YAML file
route_exists() {
    local file=$1
    local app_name=$2
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    # Check if containerApp name exists in the file
    if grep -q "containerApp: \"$app_name\"" "$file"; then
        return 0
    else
        return 1
    fi
}

# Get CAE static IP
get_cae_static_ip() {
    local cae_name=$1
    
    local static_ip=$(az containerapp env show \
        --name "$cae_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.staticIp" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -z "$static_ip" ]; then
        warning "Could not retrieve static IP for $cae_name"
        echo "<CAE_STATIC_IP>"
    else
        echo "$static_ip"
    fi
}

# Create new routing YAML file
create_new_routing_file() {
    local file=$1
    local app_name=$2
    local root_path=$3
    local cae_static_ip=$4
    
    log "Creating new routing file: $file"
    
    cat > "$file" <<EOF
# Container Apps Environment HTTP Routing Configuration
# Tenant: ${TENANT}
# Environment: ${ENV}
# CAE: ${CAE_NAME}
# Route Config Name: ${ROUTE_CONFIG_NAME}
# Note: Application Gateway handles SSL termination
# CAE uses HTTP routing without custom domains (internal CAE with static IP)
# Docs: https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing

rules:
  # Rule for ${app_name}: Route ${root_path} and ${root_path}/* to ${app_name}
  - description: "${TENANT_UPPER} routing rule for ${app_name}"
    routes:
      - match:
          prefix: "${root_path}"
    targets:
      - containerApp: "${app_name}"

# Architecture:
#   - Application Gateway: SSL termination at public IP
#   - CAE: HTTP routing via static IP (${cae_static_ip}:80)
#   - Container Apps: HTTP with allowInsecure=true
#   - Apps must handle full path including ${root_path} prefix
EOF
    
    success "Created routing file: $file"
}

# Append route to existing routing YAML file
append_route_to_file() {
    local file=$1
    local app_name=$2
    local root_path=$3
    
    log "Appending route to existing file: $file"
    
    # Create temporary file with new rule
    local temp_file=$(mktemp)
    
    # Find the line before "# Architecture:" comment
    local insert_line=$(grep -n "^# Architecture:" "$file" | cut -d: -f1)
    
    if [ -z "$insert_line" ]; then
        # If no Architecture comment, append before last line
        insert_line=$(($(wc -l < "$file")))
    fi
    
    # Insert new rule before the Architecture comment
    head -n $((insert_line - 1)) "$file" > "$temp_file"
    
    cat >> "$temp_file" <<EOF
  
  # Rule for ${app_name}: Route ${root_path} and ${root_path}/* to ${app_name}
  - description: "${TENANT_UPPER} routing rule for ${app_name}"
    routes:
      - match:
          prefix: "${root_path}"
    targets:
      - containerApp: "${app_name}"
EOF
    
    tail -n +$insert_line "$file" >> "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$file"
    
    success "Appended route to file: $file"
}

# Apply routing configuration to Container App Environment
apply_routing_config() {
    local cae_name=$1
    local route_config_name=$2
    local routing_file=$3
    
    log "Applying routing configuration to CAE: $cae_name"
    log "  Route Config Name: $route_config_name"
    log "  Routing File: $routing_file"
    
    # Check if Container App Environment exists
    if ! az containerapp env show \
        --name "$cae_name" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        error "Container App Environment not found: $cae_name"
        return 1
    fi
    
    # Try to create route config
    log "Attempting to create route configuration..."
    if az containerapp env http-route-config create \
        --name "$cae_name" \
        --resource-group "$RESOURCE_GROUP" \
        --http-route-config-name "$route_config_name" \
        --yaml "$routing_file" \
        --only-show-errors 2>&1; then
        success "Route configuration created successfully"
        return 0
    fi
    
    # If create failed, try update
    log "Create failed, attempting to update existing route configuration..."
    if az containerapp env http-route-config update \
        --name "$cae_name" \
        --resource-group "$RESOURCE_GROUP" \
        --http-route-config-name "$route_config_name" \
        --yaml "$routing_file" \
        --only-show-errors 2>&1; then
        success "Route configuration updated successfully"
        return 0
    fi
    
    error "Failed to create or update route configuration"
    return 1
}

# Main execution
main() {
    echo "================================================================================"
    log "CONFIGURE CONTAINER APP ENVIRONMENT HTTP ROUTING"
    echo "================================================================================"
    log "Script: 13-configure-cae-routing.sh"
    log "Purpose: Add/update routing rule for a Container App"
    echo "-------------------------------------------------------------------------------"
    log "Parameters:"
    log "  Environment:            $ENV"
    log "  Tenant:                 $TENANT ($TENANT_UPPER)"
    log "  CAE Name:               $CAE_NAME"
    log "  Container App:          $CONTAINER_APP_NAME"
    log "  Root Path:              $ROOT_PATH"
    echo "-------------------------------------------------------------------------------"
    log "Azure Resources:"
    log "  Resource Group:         $RESOURCE_GROUP"
    log "  Route Config Name:      $ROUTE_CONFIG_NAME"
    echo "-------------------------------------------------------------------------------"
    log "Output:"
    log "  Routing File:           $ROUTING_FILE"
    echo "================================================================================"
    echo
    
    # Check prerequisites
    check_azure_login
    
    # Ensure output directory exists
    mkdir -p "$OUTPUT_DIR"
    
    # Get CAE static IP
    CAE_STATIC_IP=$(get_cae_static_ip "$CAE_NAME")
    
    # Check if routing file exists and if route already present
    if route_exists "$ROUTING_FILE" "$CONTAINER_APP_NAME"; then
        warning "Route for $CONTAINER_APP_NAME already exists in $ROUTING_FILE"
        log "Skipping route generation (route already configured)"
    elif [ -f "$ROUTING_FILE" ]; then
        # Append to existing file
        log "Routing file exists, appending new route..."
        append_route_to_file "$ROUTING_FILE" "$CONTAINER_APP_NAME" "$ROOT_PATH"
    else
        # Create new file
        log "Routing file does not exist, creating new file..."
        create_new_routing_file "$ROUTING_FILE" "$CONTAINER_APP_NAME" "$ROOT_PATH" "$CAE_STATIC_IP"
    fi
    
    echo
    
    # Apply routing configuration
    if apply_routing_config "$CAE_NAME" "$ROUTE_CONFIG_NAME" "$ROUTING_FILE"; then
        echo
        success "Routing configured successfully!"
        log ""
        log "Route added:"
        log "  ${ROOT_PATH}/* → ${CONTAINER_APP_NAME}"
        log ""
        log "Routing file: $ROUTING_FILE"
        exit 0
    else
        echo
        error "Failed to apply routing configuration"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Configure Container App Environment HTTP Routing"
    echo
    echo "Usage: $0 ENV CAE_NAME CONTAINER_APP_NAME ROOT_PATH"
    echo
    echo "Parameters:"
    echo "  ENV                  Environment name (dev, stage, prod)"
    echo "  CAE_NAME             Container App Environment name (e.g., nbrly-dev-cae)"
    echo "  CONTAINER_APP_NAME   Container App name (e.g., ca-nbrly-nbapp1-dev)"
    echo "  ROOT_PATH            Root path for routing (e.g., /app1, /app2)"
    echo
    echo "Examples:"
    echo "  $0 dev nbrly-dev-cae ca-nbrly-nbapp1-dev /app1"
    echo "  $0 dev bloom-dev-cae ca-bloom-bmapp2-dev /app2"
    echo "  $0 stage nbrly-stage-cae ca-nbrly-nbapp1-stage /app1"
    echo
    echo "Behavior:"
    echo "  - Creates routing YAML if it doesn't exist"
    echo "  - Appends route to existing YAML if file exists"
    echo "  - Skips if route already present"
    echo "  - Applies configuration using Azure CLI"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI logged in (az login)"
    echo "  - Container App Environment deployed"
    echo "  - Container App deployed and running"
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
