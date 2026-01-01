# This script performs the following main steps:
# 1. Initializes required variables and configuration settings.
# 2. Creates necessary cloud resources such as storage accounts, virtual machines, or networking components.
# 3. Applies security and access policies to the created resources.
# 4. Validates the successful creation and configuration of resources.
# 5. Outputs relevant information or resource identifiers for further use.
#!/bin/bash

# This script is a wrapper to deploy tenant-specific infrastructure.
# It takes the tenant name, project name, and environment as arguments.

# Usage: ./02-deploy-tenant-infra.sh <tenantName> <project> [environment]
# Example: ./02-deploy-tenant-infra.sh nbrly astra dev
#          ./02-deploy-tenant-infra.sh bloom astra stage

# Exit immediately if a command exits with a non-zero status
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/helpers/logging.sh"
source "${SCRIPT_DIR}/helpers/config-parser.sh"
source "${SCRIPT_DIR}/helpers/azure-login.sh"

# Setup logging
setup_logging "tenant-infra" "$ENV"

# Trap errors and print error message
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

TENANT_NAME=$1
PROJECT=$2
ENV=${3:-dev}

if [ -z "$TENANT_NAME" ]; then
  log_error "Tenant name not provided."
  log_error "Usage: ./02-deploy-tenant-infra.sh <tenantName> <project> [environment]"
  exit 1
fi

if [ -z "$PROJECT" ]; then
  log_error "Project name not provided."
  log_error "Usage: ./02-deploy-tenant-infra.sh <tenantName> <project> [environment]"
  exit 1
fi

# Validate environment
if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
  log_error "Invalid environment: $ENV"
  log_error "Usage: ./02-deploy-tenant-infra.sh <tenantName> <project> [dev|stage|prod]"
  exit 1
fi

log_info "Starting deployment for tenant: $TENANT_NAME, project: $PROJECT (Environment: $ENV)"

# Login to Azure with environment-specific credentials
azure_login "$ENV"

# Set Azure subscription from infra file
CONFIG_DIR="$SCRIPT_DIR/../config"
INFRA_FILE="$CONFIG_DIR/infra-${ENV}.json"
SUBSCRIPTION_ID=$(parse_config "$INFRA_FILE" ".subscription.id" 2>/dev/null || echo "")

if [ -n "$SUBSCRIPTION_ID" ] && [ "$SUBSCRIPTION_ID" != "null" ]; then
    log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
else
    log_warning "No subscription ID found in infra file. Using current subscription context."
    CURRENT_SUBSCRIPTION=$(az account show --query "id" -o tsv 2>/dev/null || echo "")
    if [ -n "$CURRENT_SUBSCRIPTION" ]; then
        log_info "Current subscription: $CURRENT_SUBSCRIPTION"
    else
        log_error "No subscription context available. Please ensure you're logged in and have a valid subscription."
        exit 1
    fi
fi

log_info "Step 1: Deploying tenant resources..."
"${SCRIPT_DIR}/03-deploy-tenant-resources.sh" "$TENANT_NAME" "$ENV"
if [ $? -ne 0 ]; then
  log_error "Failed to deploy resources for tenant '$TENANT_NAME'."
  exit 1
fi

log_info "Step 2: Configuring routing..."
"${SCRIPT_DIR}/04-configure-routing.sh" "$TENANT_NAME" "$ENV"
if [ $? -ne 0 ]; then
  log_error "Failed to configure routing for tenant '$TENANT_NAME'."
  exit 1
fi

log_info "Deployment for tenant '$TENANT_NAME' (Environment: $ENV) completed successfully."
