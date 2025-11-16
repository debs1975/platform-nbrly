#!/bin/bash
set -e

# ============================================================================
# Script: setup-monitoring.sh
# Purpose: Configure monitoring and alerts for Container App
# Usage: ./setup-monitoring.sh [environment]
# ============================================================================

ENVIRONMENT=${1:-dev}

# Load application configuration from sample-app folder only
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/app-config-${ENVIRONMENT}.json"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../config/infra-config-${ENVIRONMENT}.json"

if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "❌ App configuration file not found: $APP_CONFIG_FILE"
    echo "Usage: ./setup-monitoring.sh [dev|staging|prod]"
    echo ""
    echo "Expected config file structure:"
    echo "sample-app/config/app-config-${ENVIRONMENT}.json"
    exit 1
fi

if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "❌ Infrastructure configuration file not found: $INFRA_CONFIG_FILE"
    echo "Usage: ./setup-monitoring.sh [dev|staging|prod]"
    echo ""
    echo "Expected config file structure:"
    echo "sample-app/config/infra-config-${ENVIRONMENT}.json"
    exit 1
fi

# Extract all required variables from config files
PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")
REGION=$(jq -r '.location' "$INFRA_CONFIG_FILE")
SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$INFRA_CONFIG_FILE")
ADMIN_EMAIL=$(jq -r '.monitoring.adminEmail' "$INFRA_CONFIG_FILE")

# Container App configuration
APP_NAME_SUFFIX=$(jq -r '.containerApp.nameSuffix // "ca"' "$APP_CONFIG_FILE")
CONTAINER_CPU=$(jq -r '.container.resources.cpu // "0.25"' "$APP_CONFIG_FILE")
CONTAINER_MEMORY=$(jq -r '.container.resources.memory // "0.5Gi"' "$APP_CONFIG_FILE")

# Validate required configuration
if [ "$SUBSCRIPTION_ID" == "null" ] || [ -z "$SUBSCRIPTION_ID" ]; then
    echo "❌ Missing required configuration: subscriptionId in infra config"
    exit 1
fi

if [ "$ADMIN_EMAIL" == "null" ] || [ -z "$ADMIN_EMAIL" ]; then
    echo "❌ Missing required configuration: monitoring.adminEmail in infra config"
    exit 1
fi

# ============================================================================
# Azure Authentication
# ============================================================================
echo "🔐 Checking Azure authentication..."

# Check if logged in to Azure
if ! az account show &>/dev/null; then
    echo "❌ Not logged in to Azure. Please run: az login"
    exit 1
fi

# Set the correct subscription
az account set --subscription "$SUBSCRIPTION_ID"
echo "✅ Using subscription: $SUBSCRIPTION_ID"

# Construct resource names from infrastructure config
RG_NAME=$(jq -r '.resourceGroup.name' "$INFRA_CONFIG_FILE")
APP_NAME="${PROJECT_NAME}-${ENV}-${REGION}-${APP_NAME_SUFFIX}"
ACTION_GROUP_NAME=$(jq -r '.monitoring.actionGroup.name' "$INFRA_CONFIG_FILE")
AI_NAME=$(jq -r '.monitoring.applicationInsights.name' "$INFRA_CONFIG_FILE")

# Calculate threshold values based on config
CPU_CORES=$(echo "$CONTAINER_CPU" | sed 's/[^0-9.]//g')
CPU_THRESHOLD_NANO=$(echo "$CPU_CORES * 0.8 * 1000000000" | bc -l | cut -d. -f1)

MEMORY_GB=$(echo "$CONTAINER_MEMORY" | sed 's/Gi//g')
MEMORY_THRESHOLD_BYTES=$(echo "$MEMORY_GB * 1024 * 1024 * 1024 * 0.85" | bc -l | cut -d. -f1)

echo "=========================================="
echo "Configuring Monitoring for Container App"
echo "=========================================="
echo "Environment: ${ENV}"
echo "Subscription: ${SUBSCRIPTION_ID}"
echo "Container App: ${APP_NAME}"
echo "Resource Group: ${RG_NAME}"
echo "Region: ${REGION}"
echo "CPU Threshold: ${CPU_CORES} cores (80% = ${CPU_THRESHOLD_NANO} nanocores)"
echo "Memory Threshold: ${MEMORY_GB}GB (85% = ${MEMORY_THRESHOLD_BYTES} bytes)"
echo "=========================================="

# Verify Container App exists
echo ""
echo "🔍 Verifying Container App exists..."

if ! az containerapp show --name "$APP_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "❌ Container App '$APP_NAME' not found in resource group '$RG_NAME'"
    echo ""
    echo "Available Container Apps in resource group:"
    az containerapp list --resource-group "$RG_NAME" --query "[].name" -o table 2>/dev/null || echo "  None found or resource group doesn't exist"
    echo ""
    echo "Please ensure:"
    echo "  1. The Container App is deployed"
    echo "  2. Resource names match your configuration"
    echo "  3. You have access to the resource group"
    exit 1
fi

echo "✅ Container App verified"

# Get resource IDs
echo "📋 Getting resource information..."
CONTAINER_APP_ID=$(az containerapp show \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --query id -o tsv)

ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group "$RG_NAME" \
    --name "$ACTION_GROUP_NAME" \
    --query id -o tsv 2>/dev/null || echo "")

# Create Action Group if it doesn't exist
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
        --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "ManagedBy=sample-app"
    
    ACTION_GROUP_ID=$(az monitor action-group show \
        --resource-group "$RG_NAME" \
        --name "$ACTION_GROUP_NAME" \
        --query id -o tsv)
    
    echo "✅ Action Group created: $ACTION_GROUP_NAME"
else
    echo "✅ Using existing Action Group: $ACTION_GROUP_NAME"
fi

# Get or create Application Insights
echo ""
echo "📊 Configuring Application Insights..."

APPINSIGHTS_CONN_STRING=$(az monitor app-insights component show \
    --app "$AI_NAME" \
    --resource-group "$RG_NAME" \
    --query connectionString -o tsv 2>/dev/null || echo "")

if [ -z "$APPINSIGHTS_CONN_STRING" ]; then
    echo "⚠️  Application Insights not found. Creating one..."
    
    # Get Log Analytics workspace (create if needed)
    LAW_NAME="${PROJECT_NAME}-${ENV}-${REGION}-law"
    LAW_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RG_NAME" \
        --workspace-name "$LAW_NAME" \
        --query id -o tsv 2>/dev/null || echo "")
    
    if [ -z "$LAW_ID" ]; then
        echo "Creating Log Analytics workspace..."
        az monitor log-analytics workspace create \
            --resource-group "$RG_NAME" \
            --workspace-name "$LAW_NAME" \
            --location "$REGION" \
            --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "ManagedBy=sample-app" \
            --output none
        
        LAW_ID=$(az monitor log-analytics workspace show \
            --resource-group "$RG_NAME" \
            --workspace-name "$LAW_NAME" \
            --query id -o tsv)
    fi
    
    # Create Application Insights
    az monitor app-insights component create \
        --app "$AI_NAME" \
        --location "$REGION" \
        --resource-group "$RG_NAME" \
        --workspace "$LAW_ID" \
        --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "ManagedBy=sample-app" \
        --output none
    
    APPINSIGHTS_CONN_STRING=$(az monitor app-insights component show \
        --app "$AI_NAME" \
        --resource-group "$RG_NAME" \
        --query connectionString -o tsv)
    
    echo "✅ Application Insights created: $AI_NAME"
else
    echo "✅ Using existing Application Insights: $AI_NAME"
fi

# Update Container App with Application Insights
echo "Updating Container App with Application Insights connection..."
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG_NAME" \
    --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string" \
    --secrets "appinsights-connection-string=$APPINSIGHTS_CONN_STRING" \
    --output none

echo "✅ Application Insights configured"

# Create alert rules with error handling
echo ""
echo "⚠️  Creating alert rules..."

create_alert() {
    local alert_name="$1"
    local condition="$2"
    local description="$3"
    local severity="$4"
    local window_size="${5:-5m}"
    local eval_frequency="${6:-1m}"
    
    echo "Creating alert: $alert_name..."
    
    if az monitor metrics alert create \
        --name "${APP_NAME}-${alert_name}" \
        --resource-group "$RG_NAME" \
        --scopes "$CONTAINER_APP_ID" \
        --condition "$condition" \
        --window-size "$window_size" \
        --evaluation-frequency "$eval_frequency" \
        --action "$ACTION_GROUP_ID" \
        --description "$description" \
        --severity "$severity" \
        --tags "Environment=${ENV}" "Project=${PROJECT_NAME}" "Application=sample-app" "ManagedBy=sample-app" \
        --output none 2>/dev/null; then
        echo "✅ Alert created: $alert_name"
    else
        echo "ℹ️  Alert already exists or failed to create: $alert_name"
    fi
}

# Create all alert rules
create_alert "high-restarts" \
    "avg Restarts > 5" \
    "Alert when container restarts exceed 5 in 5 minutes" \
    "2"

create_alert "high-cpu" \
    "avg UsageNanoCores > ${CPU_THRESHOLD_NANO}" \
    "Alert when CPU usage exceeds 80% (${CPU_CORES} cores allocated)" \
    "3"

create_alert "high-memory" \
    "avg WorkingSetBytes > ${MEMORY_THRESHOLD_BYTES}" \
    "Alert when memory usage exceeds 85% (${MEMORY_GB}GB allocated)" \
    "2"

create_alert "high-latency" \
    "avg HttpResponseTime > 2000" \
    "Alert when HTTP response time exceeds 2 seconds" \
    "3"

create_alert "high-errors" \
    "total Http5xxCount > 10" \
    "Alert when 5xx errors exceed 10 in 5 minutes" \
    "1"

create_alert "zero-replicas" \
    "avg Replicas == 0" \
    "Alert when app has been scaled to zero for 30 minutes" \
    "3" \
    "30m" \
    "5m"

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
echo "  2. High CPU usage (>80% of ${CPU_CORES} cores)"
echo "  3. High memory usage (>85% of ${MEMORY_GB}GB)"
echo "  4. High HTTP latency (>2s)"
echo "  5. High HTTP error rate (>10 5xx in 5 min)"
echo "  6. Scale-to-zero monitoring (0 replicas for 30 min)"
echo ""
echo "Useful Commands:"
echo "  # View alerts"
echo "  az monitor metrics alert list -g ${RG_NAME} --query \"[?contains(name, '${APP_NAME}')]\" -o table"
echo ""
echo "  # View Application Insights"
echo "  az monitor app-insights component show --app ${AI_NAME} -g ${RG_NAME}"
echo ""
echo "  # Test alert (trigger high CPU)"
echo "  az containerapp update -n ${APP_NAME} -g ${RG_NAME} --cpu 0.1 --memory 0.2Gi"
echo ""
echo "Azure Portal Links:"
echo "  Container App: https://portal.azure.com/#resource${CONTAINER_APP_ID}/overview"
echo "  Application Insights: https://portal.azure.com/#resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/microsoft.insights/components/${AI_NAME}/overview"
echo "=========================================="
