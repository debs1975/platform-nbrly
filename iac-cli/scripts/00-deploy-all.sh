#!/bin/bash

# Main deployment script to orchestrate the setup of the entire infrastructure.
# Usage: ./00-deploy-all.sh [project] [environment]
# Example: ./00-deploy-all.sh astra dev
#          ./00-deploy-all.sh astra stage
#          ./00-deploy-all.sh astra prod

# Exit immediately if a command exits with a non-zero status.
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper scripts
source "${SCRIPT_DIR}/helpers/logging.sh"

# Trap errors and print error message
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

# Get project name parameter (required)
PROJECT=${1}
if [ -z "$PROJECT" ]; then
  log_error "Project name is required"
  log_error "Usage: ./00-deploy-all.sh <project> [dev|stage|prod]"
  exit 1
fi

# Get environment parameter (default to dev if not provided)
ENV=${2:-dev}

# Validate environment
if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
  log_error "Invalid environment: $ENV"
  log_error "Usage: ./00-deploy-all.sh [dev|stage|prod]"
  exit 1
fi

log_info "======================================================"
log_info "Starting End-to-End Infrastructure Deployment"
log_info "Project: $PROJECT"
log_info "Environment: $ENV"
log_info "======================================================"

# Step 1: Deploy Common Infrastructure
log_info "Executing: 01-deploy-common-infra.sh $PROJECT $ENV"
"${SCRIPT_DIR}/01-deploy-common-infra.sh" "$PROJECT" "$ENV"
log_success "Common infrastructure deployment completed."

# Step 2: Deploy Tenant-Specific Infrastructure and Routing
log_info "Executing: 02-deploy-tenant-infra.sh nbrly $PROJECT $ENV"
"${SCRIPT_DIR}/02-deploy-tenant-infra.sh" nbrly "$PROJECT" "$ENV"
log_success "NBRLY tenant infrastructure and routing configuration completed."

log_info "Executing: 02-deploy-tenant-infra.sh bloom $PROJECT $ENV"
"${SCRIPT_DIR}/02-deploy-tenant-infra.sh" bloom "$PROJECT" "$ENV"
log_success "BLOOM tenant infrastructure and routing configuration completed."

log_info "======================================================"
log_info "End-to-End Infrastructure Deployment Finished"
log_info "Environment: $ENV"
log_info "====================================================="
