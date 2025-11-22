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

log_info "Step 1: Deploying tenant resources..."
"${SCRIPT_DIR}/03-deploy-tenant-resources.sh" "$TENANT_NAME" "$PROJECT" "$ENV"
if [ $? -ne 0 ]; then
  log_error "Failed to deploy resources for tenant '$TENANT_NAME'."
  exit 1
fi

log_info "Step 2: Configuring routing..."
"${SCRIPT_DIR}/04-configure-routing.sh" "$TENANT_NAME" "$PROJECT" "$ENV"
if [ $? -ne 0 ]; then
  log_error "Failed to configure routing for tenant '$TENANT_NAME'."
  exit 1
fi

log_info "Deployment for tenant '$TENANT_NAME' (Environment: $ENV) completed successfully."
