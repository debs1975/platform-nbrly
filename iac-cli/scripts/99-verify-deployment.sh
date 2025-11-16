#!/bin/bash
set -e
# ============================================================================
# Script: 99-verify-deployment.sh
# Purpose: Verify all infrastructure components are deployed correctly
#
# Usage:
# ./scripts/99-verify-deployment.sh [environment]
#
# Arguments:
# environment (optional) - Environment name (dev, staging, prod)
# Defaults to "dev"
#
# Examples:
# ./scripts/99-verify-deployment.sh dev
# ./scripts/99-verify-deployment.sh prod
# ============================================================================
# Color codes for output
# Default environment
ENVIRONMENT="${1:-dev}"
# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/parameters-${ENVIRONMENT}.json"
echo ""
echo "=========================================="
echo "🔍 Verifying Infrastructure Deployment"
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
# Extract variables
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
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
# Authentication details are already displayed by azure_login function
# Construct resource names
RG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-rg"
VNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-vnet"
NSG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-nsg"
KV_NAME="${PROJECT_NAME}${ENVIRONMENT}eastuskv"
UAMI_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-uami"
ACR_NAME="${PROJECT_NAME}${ENVIRONMENT}eastusacr"
CAE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-cae"
PSQL_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-psql"
LAW_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-law"
AI_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-ai"
echo "=========================================="
echo "🔍 Verifying Infrastructure Deployment"
echo "=========================================="
echo "Project: ${PROJECT_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "=========================================="
PASS_COUNT=0
FAIL_COUNT=0
# Function to check resource existence
check_resource() {
 local resource_type=$1
 local resource_name=$2
 local check_command=$3
 echo -n "Checking ${resource_type}: ${resource_name}... "
 if eval "$check_command" > /dev/null 2>&1; then
 echo "✅ PASS"
 ((PASS_COUNT++))
 return 0
 else
 echo "❌ FAIL"
 ((FAIL_COUNT++))
 return 1
 fi
}
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Layer 1: Networking"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_resource "Resource Group" "$RG_NAME" \
 "az group show --name $RG_NAME"
check_resource "Virtual Network" "$VNET_NAME" \
 "az network vnet show --resource-group $RG_NAME --name $VNET_NAME"
check_resource "NSG" "$NSG_NAME" \
 "az network nsg show --resource-group $RG_NAME --name $NSG_NAME"
check_resource "Private DNS Zone" "privatelink.postgres.database.azure.com" \
 "az network private-dns zone show --resource-group $RG_NAME --name privatelink.postgres.database.azure.com"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Layer 2: Security"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_resource "Key Vault" "$KV_NAME" \
 "az keyvault show --name $KV_NAME --resource-group $RG_NAME"
check_resource "Managed Identity" "$UAMI_NAME" \
 "az identity show --resource-group $RG_NAME --name $UAMI_NAME"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Layer 3: Compute"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_resource "Container Registry" "$ACR_NAME" \
 "az acr show --name $ACR_NAME --resource-group $RG_NAME"
check_resource "Container Apps Environment" "$CAE_NAME" \
 "az containerapp env show --name $CAE_NAME --resource-group $RG_NAME"
echo ""
echo "ℹ️ Note: Container Apps are deployed separately from application repositories."
echo " See sample-app/deploy.sh for example deployment."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Layer 4: Data"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_resource "PostgreSQL Server" "$PSQL_NAME" \
 "az postgres flexible-server show --resource-group $RG_NAME --name $PSQL_NAME"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Layer 5: Monitoring"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_resource "Log Analytics Workspace" "$LAW_NAME" \
 "az monitor log-analytics workspace show --resource-group $RG_NAME --workspace-name $LAW_NAME"
check_resource "Application Insights" "$AI_NAME" \
 "az monitor app-insights component show --app $AI_NAME --resource-group $RG_NAME"
# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "✅ Passed: $PASS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo "=========================================="
# Get application URLs
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Application Endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
FRONTEND_FQDN=$(az containerapp show \
 --resource-group "$RG_NAME" \
 --name "$FRONTEND_CA_NAME" \
 --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "N/A")
BACKEND_FQDN=$(az containerapp show \
 --resource-group "$RG_NAME" \
 --name "$BACKEND_CA_NAME" \
 --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "N/A")
echo "Frontend URL: https://${FRONTEND_FQDN}"
echo "Backend URL: https://${BACKEND_FQDN}"
# Test endpoints
echo ""
echo "Testing endpoint connectivity..."
if [ "$FRONTEND_FQDN" != "N/A" ]; then
 echo -n "Frontend HTTP test: "
 if curl -s -o /dev/null -w "%{http_code}" "https://${FRONTEND_FQDN}" | grep -q "^[23]"; then
 echo "✅ Responding"
 else
 echo "⚠️ Not responding (may be using placeholder image)"
 fi
fi
if [ "$BACKEND_FQDN" != "N/A" ]; then
 echo -n "Backend HTTP test: "
 if curl -s -o /dev/null -w "%{http_code}" "https://${BACKEND_FQDN}" | grep -q "^[23]"; then
 echo "✅ Responding"
 else
 echo "⚠️ Not responding (may be using placeholder image)"
 fi
fi
# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "✅ Passed: $PASS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo "=========================================="
if [ $FAIL_COUNT -eq 0 ]; then
 echo ""
 echo "🎉 All infrastructure components verified successfully!"
 echo ""
 echo "Next steps:"
 echo " 1. Deploy applications: cd sample-app && ./deploy.sh ${ENVIRONMENT}"
 echo " 2. View logs: az containerapp logs show --name <app-name> --resource-group $RG_NAME --follow"
 echo " 3. Monitor: Check Azure Portal → Container Apps Environment → $CAE_NAME"
 echo ""
 exit 0
else
 echo ""
 echo "⚠️ Some infrastructure components failed verification."
 echo " Review the errors above and re-run the appropriate deployment scripts."
 echo ""
 exit 1
fi
