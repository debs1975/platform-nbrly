#!/bin/bash

# Main deployment script to orchestrate the setup of the entire infrastructure.

# Exit immediately if a command exits with a non-zero status.
set -e

# Source helper scripts
source helpers/logging.sh

log_info "======================================================"
log_info "Starting End-to-End Infrastructure Deployment"
log_info "======================================================"

# Step 1: Deploy Common Infrastructure
log_info "Executing: 01-deploy-common-infra.sh"
./01-deploy-common-infra.sh
log_success "Common infrastructure deployment completed."

# Step 2: Deploy Tenant-Specific Infrastructure and Routing
log_info "Executing: 02-deploy-tenant-infra.sh"
./02-deploy-tenant-infra.sh
log_success "Tenant infrastructure and routing configuration completed."

log_info "======================================================"
log_info "End-to-End Infrastructure Deployment Finished"
log_info "======================================================"
