#!/bin/bash
set -euo pipefail

# ============================================================================
# Script: 05-deploy-monitoring.sh
# Purpose: Deploy monitoring infrastructure for nbrly environment
# Layer: 5 - Monitoring (Application Insights, Alert Rules, Diagnostics)
#
# Usage:
#   ./scripts/05-deploy-monitoring.sh [environment]
#
# Arguments:
#   environment (optional) - Environment name (dev, staging, prod)
#                           Defaults to "dev"
#
# Examples:
#   ./scripts/05-deploy-monitoring.sh dev
#   ./scripts/05-deploy-monitoring.sh prod
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
setup_logging "05-deploy-monitoring" "$ENVIRONMENT"

# Trap to ensure logging is finalized on exit
trap 'finalize_logging $?' EXIT

echo ""
echo -e "${COLOR_BLUE}=========================================="
echo -e "Layer 5: Monitoring Infrastructure"
echo -e "Environment: ${ENVIRONMENT}"
echo -e "==========================================${COLOR_RESET}"
echo ""

# Validate configuration file
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${COLOR_RED}❌ Configuration file not found: $CONFIG_FILE${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Available environments:${COLOR_RESET}"
    ls -1 "${SCRIPT_DIR}/../config/parameters-"*.json 2>/dev/null | sed 's/.*parameters-\(.*\)\.json/  - \1/' || echo "  (none found)"
    echo ""
    exit 1
fi

# Check for jq
if ! command -v jq &>/dev/null; then
    echo -e "${COLOR_RED}❌ Error: 'jq' is required but not installed${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Install with: brew install jq${COLOR_RESET}"
    exit 1
fi

echo -e "${COLOR_BLUE}📋 Loading configuration from: $CONFIG_FILE${COLOR_RESET}"

# Extract variables from config
PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
LOCATION=$(jq -r '.location' "$CONFIG_FILE")
ADMIN_EMAIL=$(jq -r '.adminEmail' "$CONFIG_FILE")

# Validate that environment in config matches parameter
if [ "$ENV" != "$ENVIRONMENT" ]; then
    echo -e "${COLOR_YELLOW}⚠️  Warning: Environment mismatch${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   Config file environment: $ENV${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   Script parameter: $ENVIRONMENT${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}   Using config file environment: $ENV${COLOR_RESET}"
    ENVIRONMENT="$ENV"
fi

echo -e "${COLOR_GREEN}✅ Configuration loaded${COLOR_RESET}"
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
LAW_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-law"
AI_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-ai"
PSQL_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-psql"
ACR_NAME="${PROJECT_NAME}${ENVIRONMENT}eastusacr"
ACTION_GROUP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-ag"

# Get Log Analytics Workspace ID
LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RG_NAME" \
    --workspace-name "$LAW_NAME" \
    --query id -o tsv)

# Tags
TAGS="Environment=${ENVIRONMENT} Project=${PROJECT_NAME} ManagedBy=AzureCLI CreatedDate=$(date +%Y-%m-%d)"

echo "=========================================="
echo "Layer 5: Monitoring Infrastructure"
echo "=========================================="
echo "Project: ${PROJECT_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Application Insights: ${AI_NAME}"
echo "=========================================="

# 1. Create Application Insights
echo ""
echo "📊 Creating Application Insights..."
az monitor app-insights component create \
    --app "$AI_NAME" \
    --location "$LOCATION" \
    --resource-group "$RG_NAME" \
    --workspace "$LAW_ID" \
    --retention-time 90 \
    --tags $TAGS

AI_INSTRUMENTATION_KEY=$(az monitor app-insights component show \
    --app "$AI_NAME" \
    --resource-group "$RG_NAME" \
    --query instrumentationKey -o tsv)

AI_CONNECTION_STRING=$(az monitor app-insights component show \
    --app "$AI_NAME" \
    --resource-group "$RG_NAME" \
    --query connectionString -o tsv)

echo "✅ Application Insights created: $AI_NAME"
echo "   Instrumentation Key: ${AI_INSTRUMENTATION_KEY:0:20}..."
echo ""
echo "ℹ️  Note: Container Apps will be configured with Application Insights"
echo "   during application deployment (see sample-app/deploy.sh)"

# 2. Enable diagnostic settings for PostgreSQL
echo ""
echo "📋 Enabling diagnostic settings for PostgreSQL..."

PSQL_ID=$(az postgres flexible-server show \
    --resource-group "$RG_NAME" \
    --name "$PSQL_NAME" \
    --query id -o tsv)

az monitor diagnostic-settings create \
    --name "${PSQL_NAME}-diagnostics" \
    --resource "$PSQL_ID" \
    --workspace "$LAW_ID" \
    --logs '[
        {
            "category": "PostgreSQLLogs",
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
        }
    ]' \
    --metrics '[
        {
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
        }
    ]'

echo "✅ PostgreSQL diagnostic settings enabled"

# 4. Enable diagnostic settings for ACR
echo ""
echo "📋 Enabling diagnostic settings for ACR..."

ACR_ID=$(az acr show \
    --name "$ACR_NAME" \
    --resource-group "$RG_NAME" \
    --query id -o tsv)

az monitor diagnostic-settings create \
    --name "${ACR_NAME}-diagnostics" \
    --resource "$ACR_ID" \
    --workspace "$LAW_ID" \
    --logs '[
        {
            "category": "ContainerRegistryRepositoryEvents",
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
        },
        {
            "category": "ContainerRegistryLoginEvents",
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
        }
    ]' \
    --metrics '[
        {
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
        }
    ]'

echo "✅ ACR diagnostic settings enabled"

# 4. Create Action Group for alerts
echo ""
echo "🔔 Creating Action Group for alert notifications..."

az monitor action-group create \
    --resource-group "$RG_NAME" \
    --name "$ACTION_GROUP_NAME" \
    --short-name "${PROJECT_NAME}-ag" \
    --email-receiver \
        name="${ENVIRONMENT}-admin" \
        email-address="$ADMIN_EMAIL" \
    --tags $TAGS

ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group "$RG_NAME" \
    --name "$ACTION_GROUP_NAME" \
    --query id -o tsv)

echo "✅ Action Group created: $ACTION_GROUP_NAME"
echo "   Email notifications will be sent to: $ADMIN_EMAIL"

# 5. Create log-based alert for failed ACR image pulls
echo ""
echo "📊 Creating log-based alert for ACR image pull failures..."

az monitor scheduled-query create \
    --name "${ACR_NAME}-failed-pulls" \
    --resource-group "$RG_NAME" \
    --scopes "$LAW_ID" \
    --condition "count 'union ContainerAppConsoleLogs_CL | where Log_s contains \"Failed to pull image\" or Log_s contains \"error pulling image\"' > 3" \
    --condition-query "union ContainerAppConsoleLogs_CL | where Log_s contains 'Failed to pull image' or Log_s contains 'error pulling image' | summarize count()" \
    --window-size 5m \
    --evaluation-frequency 5m \
    --action-groups "$ACTION_GROUP_ID" \
    --description "Alert when ACR image pull failures exceed 3 in 5 minutes" \
    --severity 2 \
    --tags $TAGS

echo "✅ Alert created: Failed ACR image pulls"
echo ""
echo "ℹ️  Note: Container App-specific alerts (restart count, CPU usage) should be"
echo "   configured during application deployment or via separate monitoring scripts."

# 6. Summary
echo ""
echo "=========================================="
echo "✅ Layer 5 Deployment Complete!"
echo "=========================================="
echo "Resources created:"
echo "  - Application Insights: $AI_NAME"
echo "    Retention: 90 days"
echo "    Workspace: $LAW_NAME"
echo "  - Diagnostic Settings:"
echo "    ✓ PostgreSQL logs → Log Analytics"
echo "    ✓ ACR logs → Log Analytics"
echo "  - Action Group: $ACTION_GROUP_NAME"
echo "    Email: $ADMIN_EMAIL"
echo "  - Alert Rules:"
echo "    ✓ ACR image pull failures"
echo "=========================================="
echo ""
echo "📊 Monitoring Setup Complete!"
echo ""
echo "Access your monitoring dashboards:"
echo "  - Application Insights: https://portal.azure.com/#resource${AI_NAME}/overview"
echo "  - Log Analytics: https://portal.azure.com/#resource${LAW_NAME}/overview"
echo ""
echo "⚠️  Alert notifications will be sent to: $ADMIN_EMAIL"
echo "   (Check inbox and confirm subscription to receive alerts)"
echo ""
echo "ℹ️  Note: Container App-specific alerts (restart count, CPU usage)"
echo "   should be configured during application deployment."
echo ""
echo "=========================================="
echo "🎉 INFRASTRUCTURE LAYERS DEPLOYED! 🎉"
echo "=========================================="
echo -e "${COLOR_GREEN}Next: Deploy applications using sample-app/deploy.sh ${ENVIRONMENT}${COLOR_RESET}"
echo ""

