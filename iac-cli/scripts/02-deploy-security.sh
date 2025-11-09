#!/bin/bash
set -euo pipefail

# ============================================================================
# Script: 02-deploy-security.sh
# Purpose: Deploy security infrastructure for nbrly environment
# Layer: 2 - Security (Key Vault, Managed Identity, RBAC)
#
# Usage:
#   ./scripts/02-deploy-security.sh [environment]
#
# Arguments:
#   environment (optional) - Environment name (dev, staging, prod)
#                           Defaults to "dev"
#
# Examples:
#   ./scripts/02-deploy-security.sh dev
#   ./scripts/02-deploy-security.sh prod
# ============================================================================

# Color codes for output
if [[ -z "${COLOR_RED:-}" ]]; then
    readonly COLOR_RED='\033[0;31m'
fi
if [[ -z "${COLOR_GREEN:-}" ]]; then
    readonly COLOR_GREEN='\033[0;32m'
fi
if [[ -z "${COLOR_YELLOW:-}" ]]; then
    readonly COLOR_YELLOW='\033[1;33m'
fi
if [[ -z "${COLOR_BLUE:-}" ]]; then
    readonly COLOR_BLUE='\033[0;34m'
fi
if [[ -z "${COLOR_RESET:-}" ]]; then
    readonly COLOR_RESET='\033[0m'
fi

# Default environment
ENVIRONMENT="${1:-dev}"

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/parameters-${ENVIRONMENT}.json"

# Setup logging
source "${SCRIPT_DIR}/helpers/logging.sh"
setup_logging "02-deploy-security" "$ENVIRONMENT"

# Trap to ensure logging is finalized on exit
trap 'finalize_logging $?' EXIT

log_info "=========================================="
log_info "Layer 2: Security Infrastructure"
log_info "Environment: ${ENVIRONMENT}"
log_info "=========================================="
echo ""

# Validate configuration file
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_warning "Available environments:"
    ls -1 "${SCRIPT_DIR}/../config/parameters-"*.json 2>/dev/null | sed 's/.*parameters-\(.*\)\.json/  - \1/' || echo "  (none found)"
    echo ""
    exit 1
fi

# Check for jq
if ! command -v jq &>/dev/null; then
    log_error "'jq' is required but not installed"
    log_info "Install with: brew install jq"
    exit 1
fi

log_info "📋 Loading configuration from: $CONFIG_FILE"

# Extract variables from config
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
LOCATION=$(jq -r '.location' "$CONFIG_FILE")
ADMIN_EMAIL=$(jq -r '.adminEmail' "$CONFIG_FILE")

# Validate that environment in config matches parameter
if [ "$ENV" != "$ENVIRONMENT" ]; then
    log_warning "Environment mismatch"
    log_warning "  Config file environment: $ENV"
    log_warning "  Script parameter: $ENVIRONMENT"
    log_warning "  Using config file environment: $ENV"
    ENVIRONMENT="$ENV"
fi

log_success "Configuration loaded"
echo ""

# ============================================================================
# Azure Authentication
# ============================================================================
source "${SCRIPT_DIR}/helpers/azure-login.sh"
azure_login "$ENVIRONMENT"

# Log to file only (console display already handled by azure_login)
log_auth_details

# Construct resource names (lowercase)
RG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-rg"
KV_NAME="${PROJECT_NAME}${ENVIRONMENT}eastuskv"
UAMI_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-uami"
ACR_NAME="${PROJECT_NAME}${ENVIRONMENT}eastusacr"

# Get current identity (user or service principal) for Key Vault permissions
ACCOUNT_TYPE=$(az account show --query user.type -o tsv)
if [[ "$ACCOUNT_TYPE" == "servicePrincipal" ]]; then
    # For service principal, get the object ID from the service principal
    CURRENT_USER_NAME=$(az account show --query user.name -o tsv)
    CURRENT_USER_OBJECT_ID=$(az ad sp show --id "$CURRENT_USER_NAME" --query id -o tsv)
    log_info "Using Service Principal Object ID: $CURRENT_USER_OBJECT_ID"
else
    # For regular user accounts
    CURRENT_USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
    log_info "Using User Object ID: $CURRENT_USER_OBJECT_ID"
fi

# Tags
TAGS="Environment=${ENVIRONMENT} Project=${PROJECT_NAME} ManagedBy=AzureCLI CreatedDate=$(date +%Y-%m-%d)"

echo "=========================================="
echo "Layer 2: Security Infrastructure"
echo "=========================================="
echo "Project: ${PROJECT_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Key Vault: ${KV_NAME}"
echo "Managed Identity: ${UAMI_NAME}"
echo "=========================================="

# 1. Create User-Assigned Managed Identity
echo ""
echo "🔑 Creating User-Assigned Managed Identity..."

# Check if User-Assigned Managed Identity already exists
if az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" &>/dev/null; then
    log_info "User-Assigned Managed Identity '$UAMI_NAME' already exists, skipping creation"
else
    log_info "Creating User-Assigned Managed Identity '$UAMI_NAME'..."
    az identity create \
        --resource-group "$RG_NAME" \
        --name "$UAMI_NAME" \
        --location "$LOCATION" \
        --tags $TAGS
fi

UAMI_PRINCIPAL_ID=$(az identity show \
    --resource-group "$RG_NAME" \
    --name "$UAMI_NAME" \
    --query principalId -o tsv)

UAMI_CLIENT_ID=$(az identity show \
    --resource-group "$RG_NAME" \
    --name "$UAMI_NAME" \
    --query clientId -o tsv)

log_success "Managed Identity created: $UAMI_NAME"
log_info "  Principal ID: $UAMI_PRINCIPAL_ID"
log_info "  Client ID: $UAMI_CLIENT_ID"

# 2. Create Key Vault
echo ""
echo "🔐 Creating Key Vault..."

# Check if Key Vault already exists
if az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    log_info "Key Vault '$KV_NAME' already exists, skipping creation"
else
    log_info "Creating Key Vault '$KV_NAME'..."
    az keyvault create \
        --resource-group "$RG_NAME" \
        --name "$KV_NAME" \
        --location "$LOCATION" \
        --enable-rbac-authorization true \
        --retention-days 90 \
        --tags $TAGS
    log_success "Key Vault created: $KV_NAME"
fi

log_success "Key Vault created: $KV_NAME"
log_info "Note: Soft delete is enabled with 90-day retention (default)"
log_info "Purge protection is not enabled (can be enabled later if needed for production)"

# 3. Assign RBAC roles for Key Vault
echo ""
echo "🔒 Assigning RBAC roles for Key Vault..."

# Give current user Key Vault Administrator role (for secret management)
az role assignment create \
    --assignee "$CURRENT_USER_OBJECT_ID" \
    --role "Key Vault Administrator" \
    --scope $(az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" --query id -o tsv)

log_success "Current user assigned Key Vault Administrator role"

# Give managed identity Key Vault Secrets User role
az role assignment create \
    --assignee "$UAMI_PRINCIPAL_ID" \
    --role "Key Vault Secrets User" \
    --scope $(az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" --query id -o tsv)

log_success "Managed Identity assigned Key Vault Secrets User role"

# Wait for role assignment propagation
echo "⏳ Waiting for role assignments to propagate (30 seconds)..."
sleep 30

# 4. Assign AcrPull role to Managed Identity (ACR will be created in next layer)
# Note: This will be done in the compute layer after ACR is created

echo ""
echo "ℹ️  Note: AcrPull role assignment will be done in Layer 3 (after ACR creation)"

# 5. Create placeholder secrets in Key Vault
echo ""
echo "🔑 Creating placeholder secrets in Key Vault..."

# PostgreSQL connection string placeholder
az keyvault secret set \
    --vault-name "$KV_NAME" \
    --name "postgres-connection-string" \
    --value "postgresql://dbadmin:PLACEHOLDER@${PROJECT_NAME}-${ENVIRONMENT}-eastus-psql.postgres.database.azure.com/${PROJECT_NAME}?sslmode=require" \
    --description "PostgreSQL connection string (update after DB creation)"

# API secret key
API_SECRET=$(openssl rand -hex 32)
az keyvault secret set \
    --vault-name "$KV_NAME" \
    --name "api-secret-key" \
    --value "$API_SECRET" \
    --description "FastAPI JWT signing key"

# Frontend API URL placeholder
az keyvault secret set \
    --vault-name "$KV_NAME" \
    --name "frontend-api-url" \
    --value "https://${PROJECT_NAME}-${ENVIRONMENT}-eastus-backend-ca.azurecontainerapps.io" \
    --description "Backend API endpoint URL for frontend"

log_success "Placeholder secrets created in Key Vault"

# Summary
echo ""
echo "=========================================="
echo "✅ Layer 2 Deployment Complete!"
echo "=========================================="
echo "Resources created:"
echo "  - User-Assigned Managed Identity: $UAMI_NAME"
echo "    Principal ID: $UAMI_PRINCIPAL_ID"
echo "    Client ID: $UAMI_CLIENT_ID"
echo "  - Key Vault: $KV_NAME"
echo "  - RBAC Assignments:"
echo "    ✓ Current user -> Key Vault Administrator"
echo "    ✓ Managed Identity -> Key Vault Secrets User"
echo "  - Secrets:"
echo "    ✓ postgres-connection-string (placeholder)"
echo "    ✓ api-secret-key (generated)"
echo "    ✓ frontend-api-url (placeholder)"
echo "=========================================="
echo ""
echo "⚠️  Important: Update 'postgres-connection-string' secret after database creation in Layer 4"
echo ""
echo -e "${COLOR_GREEN}Next step: Run ./03-deploy-compute.sh ${ENVIRONMENT}${COLOR_RESET}"
echo ""
