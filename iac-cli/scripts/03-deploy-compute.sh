#!/bin/bash
set -euo pipefail
# ============================================================================
# Script: 03-deploy-compute.sh
# Purpose: Deploy compute infrastructure for nbrly environment
# Layer: 3 - Compute (ACR, Container Apps Environment, Container Apps)
#
# Usage:
# ./scripts/03-deploy-compute.sh [environment]
#
# Arguments:
# environment (optional) - Environment name (dev, staging, prod)
# Defaults to "dev"
#
# Examples:
# ./scripts/03-deploy-compute.sh dev
# ./scripts/03-deploy-compute.sh prod
# ============================================================================
# Color codes for output
# Default environment
ENVIRONMENT="${1:-dev}"
# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/parameters-${ENVIRONMENT}.json"
# Setup logging
source "${SCRIPT_DIR}/helpers/logging.sh"
setup_logging "03-deploy-compute" "$ENVIRONMENT"
# Trap to ensure logging is finalized on exit
trap 'finalize_logging $?' EXIT
echo ""
echo "=========================================="
echo "Layer 3: Compute Infrastructure"
echo "Environment: ${ENVIRONMENT}"
echo "=========================================="
echo ""
# Validate configuration file
if [ ! -f "$CONFIG_FILE" ]; then
 echo "❌ Configuration file not found: $CONFIG_FILE"
 echo "Available environments:"
 ls -1 "${SCRIPT_DIR}/../config/parameters-"*.json 2>/dev/null | sed 's/.*parameters-\(.*\)\.json/ - \1/' || echo " (none found)"
 echo ""
 exit 1
fi
# Check for jq
if ! command -v jq &>/dev/null; then
 echo "❌ Error: 'jq' is required but not installed"
 echo "Install with: brew install jq"
 exit 1
fi
echo "📋 Loading configuration from: $CONFIG_FILE"
# Extract variables from config
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
LOCATION=$(jq -r '.location' "$CONFIG_FILE")
CONTAINER_APPS_MAX_REPLICAS=$(jq -r '.containerAppsMaxReplicas' "$CONFIG_FILE")
# Validate that environment in config matches parameter
if [ "$ENV" != "$ENVIRONMENT" ]; then
 echo "⚠️ Warning: Environment mismatch"
 echo " Config file environment: $ENV"
 echo " Script parameter: $ENVIRONMENT"
 echo " Using config file environment: $ENV"
 ENVIRONMENT="$ENV"
fi
echo "✅ Configuration loaded"
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
ACR_NAME="${PROJECT_NAME}${ENVIRONMENT}eastusacr"
CAE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-cae"
FRONTEND_CA_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-frontend-ca"
BACKEND_CA_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-backend-ca"
UAMI_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-uami"
VNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-vnet"
SUBNET_CAE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-subnet-cae"
LAW_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-law"
KV_NAME="${PROJECT_NAME}${ENVIRONMENT}eastuskv"
# Get Managed Identity details
UAMI_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query id -o tsv)
UAMI_PRINCIPAL_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query principalId -o tsv)
UAMI_CLIENT_ID=$(az identity show --resource-group "$RG_NAME" --name "$UAMI_NAME" --query clientId -o tsv)
# Get Subnet ID
SUBNET_ID=$(az network vnet subnet show \
 --resource-group "$RG_NAME" \
 --vnet-name "$VNET_NAME" \
 --name "$SUBNET_CAE_NAME" \
 --query id -o tsv)
# Tags
TAGS="Environment=${ENVIRONMENT} Project=${PROJECT_NAME} ManagedBy=AzureCLI CreatedDate=$(date +%Y-%m-%d)"
echo "=========================================="
echo "Layer 3: Compute Infrastructure"
echo "=========================================="
echo "Project: ${PROJECT_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "ACR: ${ACR_NAME}"
echo "Container Apps Environment: ${CAE_NAME}"
echo "=========================================="
# 1. Create Azure Container Registry
echo ""
echo "📦 Creating Azure Container Registry..."
if ! az acr show --name "$ACR_NAME" --resource-group "$RG_NAME" --output none 2>/dev/null; then
 az acr create \
 --resource-group "$RG_NAME" \
 --name "$ACR_NAME" \
 --location "$LOCATION" \
 --sku Basic \
 --admin-enabled false \
 --tags $TAGS
 echo "✅ ACR created: $ACR_NAME"
else
 echo "ℹ️ ACR already exists: $ACR_NAME"
fi
# 2. Assign AcrPull role to Managed Identity
echo ""
echo "🔒 Assigning AcrPull role to Managed Identity..."
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RG_NAME" --query id -o tsv)
az role assignment create \
 --assignee "$UAMI_PRINCIPAL_ID" \
 --role "AcrPull" \
 --scope "$ACR_ID"
echo "✅ Managed Identity assigned AcrPull role on ACR"
echo "⏳ Waiting for role assignment to propagate (30 seconds)..."
sleep 30
# 3. Create Log Analytics Workspace (needed for Container Apps Environment)
echo ""
echo "📊 Creating Log Analytics Workspace..."
if ! az monitor log-analytics workspace show --resource-group "$RG_NAME" --workspace-name "$LAW_NAME" --output none 2>/dev/null; then
 az monitor log-analytics workspace create \
 --resource-group "$RG_NAME" \
 --workspace-name "$LAW_NAME" \
 --location "$LOCATION" \
 --retention-time 30 \
 --tags $TAGS
 echo "✅ Log Analytics Workspace created: $LAW_NAME"
else
 echo "ℹ️ Log Analytics Workspace already exists: $LAW_NAME"
fi
LAW_ID=$(az monitor log-analytics workspace show \
 --resource-group "$RG_NAME" \
 --workspace-name "$LAW_NAME" \
 --query customerId -o tsv)
LAW_KEY=$(az monitor log-analytics workspace get-shared-keys \
 --resource-group "$RG_NAME" \
 --workspace-name "$LAW_NAME" \
 --query primarySharedKey -o tsv)
# 4. Create Container Apps Environment
echo ""

echo "🏗️ Creating Container Apps Environment..."
if ! az containerapp env show --name "$CAE_NAME" --resource-group "$RG_NAME" --output none 2>/dev/null; then
 az containerapp env create \
 --resource-group "$RG_NAME" \
 --name "$CAE_NAME" \
 --location "$LOCATION" \
 --infrastructure-subnet-resource-id "$SUBNET_ID" \
 --logs-workspace-id "$LAW_ID" \
 --logs-workspace-key "$LAW_KEY" \
 --tags $TAGS
 echo "✅ Container Apps Environment created: $CAE_NAME"
else
 echo "ℹ️ Container Apps Environment already exists: $CAE_NAME"
fi
echo "✅ Container Apps Environment created: $CAE_NAME"

# 5. Assign Managed Identity to Container Apps Environment
echo ""
echo "🔐 Assigning User-Assigned Managed Identity to Container Apps Environment..."

# Check if UAMI is already assigned to the Container Apps Environment
CAE_IDENTITY=$(az containerapp env show \
    --name "$CAE_NAME" \
    --resource-group "$RG_NAME" \
    --query "identity.userAssignedIdentities" -o tsv 2>/dev/null)

if [[ "$CAE_IDENTITY" == *"$UAMI_ID"* ]]; then
    echo "ℹ️ User-Assigned Managed Identity already assigned to Container Apps Environment"
else
    echo "🔧 Assigning User-Assigned Managed Identity to Container Apps Environment..."
    az containerapp env identity assign \
        --name "$CAE_NAME" \
        --resource-group "$RG_NAME" \
        --user-assigned "$UAMI_ID"
    echo "✅ User-Assigned Managed Identity assigned to Container Apps Environment"
fi
# Note: Individual Container Apps should be deployed from application source repositories
# See sample-app/ directory for example deployment scripts
# Summary

echo ""
echo "=========================================="
echo "✅ Layer 3 Deployment Complete!"
echo "=========================================="
echo "Resources created:"
echo " - Azure Container Registry: $ACR_NAME"
echo " Login Server: ${ACR_NAME}.azurecr.io"
echo " - Log Analytics Workspace: $LAW_NAME"
echo " - Container Apps Environment: $CAE_NAME"
echo " VNet Integrated: Yes"
echo " Infrastructure Subnet: $SUBNET_CAE_NAME"
echo " - RBAC: Managed Identity has AcrPull on ACR"
echo "=========================================="
echo ""
echo "ℹ️ Container Apps Environment is ready for application deployments"
echo ""
echo "Next steps:"
echo " 1. Deploy applications from source repositories (see sample-app/)"
echo " 2. Run ./04-deploy-data.sh ${ENVIRONMENT} to deploy PostgreSQL database"
echo ""
