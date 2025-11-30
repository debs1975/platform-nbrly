#!/bin/bash

# Deploy Container Apps using YAML Manifests
# Alternative to the Azure CLI imperative deployment scripts
# Orchestrates deployment by calling 08-deploy-yaml-nbrly.sh and 09-deploy-yaml-bloom.sh
#
# USAGE:
#   ./07-deploy-yaml.sh [TAG]
#
# PARAMETERS:
#   TAG    (Optional) Docker image tag to deploy. Default: 'latest'
#          Updates YAML manifests with this tag before deployment
#
# EXAMPLES:
#   ./07-deploy-yaml.sh                   # Deploy with 'latest' tag
#   ./07-deploy-yaml.sh v1.0.0            # Deploy specific version
#   ./07-deploy-yaml.sh dev-123           # Deploy dev build
#
# PREREQUISITES:
#   - Azure CLI logged in (az login)
#   - Container Apps extension installed
#   - YAML manifests in manifests/.generated/
#   - Images available in ACR with specified TAG
#
# WORKFLOW:
#   1. Calls 08-deploy-yaml-nbrly.sh for NBRLY tenant
#   2. Calls 09-deploy-yaml-bloom.sh for BLOOM tenant

set -euo pipefail

# Load configuration - preserve SCRIPT_DIR before config-loader redefines it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT_DIR="$SCRIPT_DIR"  # Preserve for later use
source "$SCRIPT_DIR/helpers/config-loader.sh"

# Configuration
ENV=${ENV:-"dev"}
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resourceGroup.name")
MANIFESTS_DIR="$MAIN_SCRIPT_DIR/../manifests/.generated"
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

# Main execution
main() {
    echo "================================================================================"
    log "DEPLOY ALL APPS USING YAML MANIFESTS (ORCHESTRATOR)"
    echo "================================================================================"
    log "Purpose: Deploy all apps using declarative YAML manifests"
    log "         Calls 08-deploy-yaml-nbrly.sh and 09-deploy-yaml-bloom.sh"
    log "Environment: $ENV"
    log "Resource Group: $RESOURCE_GROUP"
    log "Image Tag: $TAG"
    echo "================================================================================"
    echo
    
    # Check prerequisites
    check_azure_login
    check_containerapp_extension
    check_jq || exit 1
    
    # Deploy NBRLY tenant
    log "Deploying NBRLY tenant applications..."
    if "$MAIN_SCRIPT_DIR/08-deploy-yaml-nbrly.sh" "$TAG"; then
        success "NBRLY tenant deployed successfully"
    else
        error "Failed to deploy NBRLY tenant"
        exit 1
    fi
    
    echo
    
    # Deploy BLOOM tenant
    log "Deploying BLOOM tenant applications..."
    if "$MAIN_SCRIPT_DIR/09-deploy-yaml-bloom.sh" "$TAG"; then
        success "BLOOM tenant deployed successfully"
    else
        error "Failed to deploy BLOOM tenant"
        exit 1
    fi
    
    # Summary
    success "All Container Apps deployed successfully using YAML manifests!"
    
    log ""
    log "Next steps:"
    log "1. Configure Application Gateway routing: ./10-configure-routing.sh"
    log "2. Test the applications: ./test-routing.sh"
    log "3. Set up custom domains and SSL certificates"
    
    exit 0
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
    local acr_name=$(get_infra_value "$ENV" ".containerRegistry.name" 2>/dev/null || echo "<ACR_NAME>")
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