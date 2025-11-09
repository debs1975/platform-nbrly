#!/bin/bash
set -e

# ============================================================================
# Script: setup-monitoring.sh
# Purpose: Configure monitoring and alerts for Container App
# Usage: ./setup-monitoring.sh [environment]
# ============================================================================

ENVIRONMENT=${1:-dev}

# Load infrastructure and application configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../../iac-cli/config/parameters-${ENVIRONMENT}.json"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/app-config-${ENVIRONMENT}.json"

if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "Configuration file not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./setup-monitoring.sh [dev|staging|prod]"
    exit 1
fi

if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "App configuration file not found: $APP_CONFIG_FILE"
    echo "Usage: ./setup-monitoring.sh [dev|staging|prod]"
    exit 1
fi

# Extract variables from infrastructure config
PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")
ADMIN_EMAIL=$(jq -r '.adminEmail' "$INFRA_CONFIG_FILE")

# Extract variables from app config
APP_NAME_SUFFIX=$(jq -r '.containerApp.nameSuffix' "$APP_CONFIG_FILE")
CONTAINER_CPU=$(jq -r '.containerApp.resources.cpu' "$APP_CONFIG_FILE")
CONTAINER_MEMORY=$(jq -r '.containerApp.resources.memory' "$APP_CONFIG_FILE")

# ============================================================================
# Azure Authentication
# ============================================================================
source "${SCRIPT_DIR}/../../iac-cli/scripts/helpers/azure-login.sh"
azure_login "$ENV"

# Construct resource names
RG_NAME="${PROJECT_NAME}-${ENV}-eastus-rg"
APP_NAME="${PROJECT_NAME}-${ENV}-eastus-${APP_NAME_SUFFIX}"
ACTION_GROUP_NAME="${PROJECT_NAME}-${ENV}-eastus-ag"
AI_NAME="${PROJECT_NAME}-${ENV}-eastus-ai"

# Calculate threshold values based on config
CPU_CORES=$(echo "$CONTAINER_CPU" | sed 's/[^0-9.]//g')
CPU_THRESHOLD_NANO=$(echo "$CPU_CORES * 0.8 * 1000000000" | bc | cut -d. -f1)

MEMORY_GB=$(echo "$CONTAINER_MEMORY" | sed 's/Gi//g')
MEMORY_THRESHOLD_BYTES=$(echo "$MEMORY_GB * 1024 * 1024 * 1024 * 0.85" | bc | cut -d. -f1)

echo "=========================================="
echo "Configuring Monitoring for Container App"
echo "=========================================="
echo "Environment: ${ENV}"
echo "Container App: ${APP_NAME}"
echo "Resource Group: ${RG_NAME}"
echo "=========================================="

# Verify Container App exists
echo ""
echo "🔍 Verifying Container App exists..."

if ! az containerapp show --name "$APP_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "❌ Container App not found. Deploy the application first:"
    echo "   cd sample-app && ./scripts/deploy.sh ${ENV}"
    exit 1
fi

echo "✅ Container App verified"

# Get resource IDs
CONTAINER_APP_ID=$(az containerapp show \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --query id -o tsv)

ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group "$RG_NAME" \
    --name "$ACTION_GROUP_NAME" \
    --query id -o tsv 2>/dev/null || echo "")

if [ -z "$ACTION_GROUP_ID" ]; then
    echo "⚠️  Action Group not found. Creating one..."
    
    az monitor action-group create \
        --resource-group "$RG_NAME" \
        --name "$ACTION_GROUP_NAME" \
        --short-name "${PROJECT_NAME}-ag" \
        --email-receiver \
            name="${PROJECT_NAME}-admin" \
            email="$ADMIN_EMAIL" \
            use-common-alert-schema=true \
        --tags "Environment=${ENV}" "Project=${PROJECT_NAME}"
    
    ACTION_GROUP_ID=$(az monitor action-group show \
        --resource-group "$RG_NAME" \
        --name "$ACTION_GROUP_NAME" \
        --query id -o tsv)
    
    echo "✅ Action Group created: $ACTION_GROUP_NAME"
else
    echo "✅ Using existing Action Group: $ACTION_GROUP_NAME"
fi

# Get Application Insights connection string
echo ""
echo "📊 Configuring Application Insights..."

APPINSIGHTS_CONN_STRING=$(az monitor app-insights component show \
    --app "$AI_NAME" \
    --resource-group "$RG_NAME" \
    --query connectionString -o tsv 2>/dev/null || echo "")

if [ -z "$APPINSIGHTS_CONN_STRING" ]; then
    echo "⚠️  Application Insights not found. Run infrastructure deployment first:"
    echo "   ./iac-cli/scripts/05-deploy-monitoring.sh ${ENV}"
    exit 1
fi

# Update Container App with Application Insights
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG_NAME" \
    --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CONN_STRING" \
    --output none

echo "✅ Application Insights configured"

# Create alert rules
echo ""
echo "⚠️  Creating alert rules..."

# Alert 1: High Restart Count
echo "Creating alert: High restart count..."
az monitor metrics alert create \
    --name "${APP_NAME}-high-restarts" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg Restarts > 5" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when container restarts exceed 5 in 5 minutes" \
    --severity 2 \
    --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=sample-api" \
    --output none 2>/dev/null || echo "  (Alert may already exist)"

echo "✅ Alert created: High restart count"

# Alert 2: High CPU Usage
echo "Creating alert: High CPU usage..."
az monitor metrics alert create \
    --name "${APP_NAME}-high-cpu" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg UsageNanoCores > ${CPU_THRESHOLD_NANO}" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when CPU usage exceeds 80% (${CPU_CORES} cores allocated)" \
    --severity 3 \
    --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=sample-api" \
    --output none 2>/dev/null || echo "  (Alert may already exist)"

echo "✅ Alert created: High CPU usage"

# Alert 3: High Memory Usage
echo "Creating alert: High memory usage..."
az monitor metrics alert create \
    --name "${APP_NAME}-high-memory" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg WorkingSetBytes > ${MEMORY_THRESHOLD_BYTES}" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when memory usage exceeds 85% (${MEMORY_GB}GB allocated)" \
    --severity 2 \
    --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=sample-api" \
    --output none 2>/dev/null || echo "  (Alert may already exist)"

echo "✅ Alert created: High memory usage"

# Alert 4: High HTTP Latency
echo "Creating alert: High HTTP latency..."
az monitor metrics alert create \
    --name "${APP_NAME}-high-latency" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg HttpResponseTime > 2000" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when HTTP response time exceeds 2 seconds" \
    --severity 3 \
    --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=sample-api" \
    --output none 2>/dev/null || echo "  (Alert may already exist)"

echo "✅ Alert created: High HTTP latency"

# Alert 5: HTTP Error Rate
echo "Creating alert: High HTTP error rate..."
az monitor metrics alert create \
    --name "${APP_NAME}-high-errors" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "total Http5xxCount > 10" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when 5xx errors exceed 10 in 5 minutes" \
    --severity 1 \
    --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=sample-api" \
    --output none 2>/dev/null || echo "  (Alert may already exist)"

echo "✅ Alert created: High HTTP error rate"

# Alert 6: Scale to Zero Monitoring
echo "Creating alert: Scale-to-zero monitoring..."
az monitor metrics alert create \
    --name "${APP_NAME}-zero-replicas" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg Replicas == 0" \
    --window-size 30m \
    --evaluation-frequency 5m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when app has been scaled to zero for 30 minutes" \
    --severity 3 \
    --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=sample-api" \
    --output none 2>/dev/null || echo "  (Alert may already exist)"

echo "✅ Alert created: Scale-to-zero monitoring"

# Summary
echo ""
echo "=========================================="
echo "✅ Monitoring Configuration Complete!"
echo "=========================================="
echo "Container App: ${APP_NAME}"
echo "Application Insights: ${AI_NAME}"
echo "Action Group: ${ACTION_GROUP_NAME}"
echo "Alert notifications: ${ADMIN_EMAIL}"
echo ""
echo "Alert Rules Created:"
echo "  1. High restart count (>5 in 5 min)"
echo "  2. High CPU usage (>80%)"
echo "  3. High memory usage (>85%)"
echo "  4. High HTTP latency (>2s)"
echo "  5. High HTTP error rate (>10 5xx in 5 min)"
echo "  6. Scale-to-zero monitoring (0 replicas for 30 min)"
echo ""
echo "View alerts:"
echo "  az monitor metrics alert list -g ${RG_NAME} --query \"[?contains(name, '${APP_NAME}')]\" -o table"
echo ""
echo "Application Insights:"
echo "  https://portal.azure.com/#resource${CONTAINER_APP_ID}/overview"
echo ""
echo "Documentation:"
echo "  See docs/monitoring-alerts.md for alert details and investigation steps"
echo "=========================================="
