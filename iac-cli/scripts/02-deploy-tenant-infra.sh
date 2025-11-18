#!/bin/bash

# This script is a wrapper to deploy tenant-specific infrastructure.
# It takes the tenant name as an argument.

# Usage: ./02-deploy-tenant-infra.sh <tenantName>
# Example: ./02-deploy-tenant-infra.sh nbrly

source ./helpers/logging.sh

TENANT_NAME=$1

if [ -z "$TENANT_NAME" ]; then
  log_error "Tenant name not provided."
  log_error "Usage: ./02-deploy-tenant-infra.sh <tenantName>"
  exit 1
fi

TENANT_SCRIPT_DIR="./${TENANT_NAME}"

if [ ! -d "$TENANT_SCRIPT_DIR" ]; then
  log_error "Scripts for tenant '$TENANT_NAME' not found at '$TENANT_SCRIPT_DIR'."
  exit 1
fi

log_info "Starting deployment for tenant: $TENANT_NAME"

log_info "Step 1: Deploying tenant resources..."
bash "${TENANT_SCRIPT_DIR}/01-deploy-tenant-resources.sh"
if [ $? -ne 0 ]; then
  log_error "Failed to deploy resources for tenant '$TENANT_NAME'."
  exit 1
fi

log_info "Step 2: Configuring routing..."
bash "${TENANT_SCRIPT_DIR}/02-configure-routing.sh"
if [ $? -ne 0 ]; then
  log_error "Failed to configure routing for tenant '$TENANT_NAME'."
  exit 1
fi

log_info "Deployment for tenant '$TENANT_NAME' completed successfully."
