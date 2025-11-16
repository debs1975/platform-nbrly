#!/bin/bash
set -euo pipefail
# ============================================================================
# Script: 04-deploy-data.sh
# Purpose: Deploy data infrastructure for nbrly environment
# Layer: 4 - Data (PostgreSQL Flexible Server, Private Endpoint)
#
# Usage:
# ./scripts/04-deploy-data.sh [environment]
#
# Arguments:
# environment (optional) - Environment name (dev, staging, prod)
# Defaults to "dev"
#
# Examples:
# ./scripts/04-deploy-data.sh dev
# ./scripts/04-deploy-data.sh prod
# ============================================================================
# Color codes for output
# Default environment
ENVIRONMENT="${1:-dev}"
# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/parameters-${ENVIRONMENT}.json"
# Setup logging
source "${SCRIPT_DIR}/helpers/logging.sh"
setup_logging "04-deploy-data" "$ENVIRONMENT"
# Trap to ensure logging is finalized on exit
trap 'finalize_logging $?' EXIT
echo ""
echo "=========================================="
echo "Layer 4: Data Infrastructure"
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
DATABASE_SKU=$(jq -r '.databaseSkuName' "$CONFIG_FILE")
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
PSQL_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-psql"
PE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-psql-pe"
VNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-vnet"
SUBNET_PE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eastus-subnet-pe"
PRIVATE_DNS_ZONE="privatelink.postgres.database.azure.com"
KV_NAME="${PROJECT_NAME}${ENVIRONMENT}eastuskv"
# Database configuration
DB_ADMIN_USER="dbadmin"
DB_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
DB_NAME="${PROJECT_NAME}"
DB_VERSION="16"
DB_STORAGE_SIZE_GB="32"
DB_BACKUP_RETENTION_DAYS="7"
# Get Subnet ID
SUBNET_PE_ID=$(az network vnet subnet show \
 --resource-group "$RG_NAME" \
 --vnet-name "$VNET_NAME" \
 --name "$SUBNET_PE_NAME" \
 --query id -o tsv)
# Tags
TAGS="Environment=${ENVIRONMENT} Project=${PROJECT_NAME} ManagedBy=AzureCLI CreatedDate=$(date +%Y-%m-%d)"
echo "=========================================="
echo "Layer 4: Data Infrastructure"
echo "=========================================="
echo "Project: ${PROJECT_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "PostgreSQL Server: ${PSQL_NAME}"
echo "=========================================="
# 1. Create PostgreSQL Flexible Server
echo ""
echo "🗄️ Creating PostgreSQL Flexible Server..."
echo " This may take 10-15 minutes..."
az postgres flexible-server create \
 --resource-group "$RG_NAME" \
 --name "$PSQL_NAME" \
 --location "$LOCATION" \
 --admin-user "$DB_ADMIN_USER" \
 --admin-password "$DB_ADMIN_PASSWORD" \
 --sku-name "$DATABASE_SKU" \
 --tier Burstable \
 --version "$DB_VERSION" \
 --storage-size "$DB_STORAGE_SIZE_GB" \
 --backup-retention "$DB_BACKUP_RETENTION_DAYS" \
 --high-availability Disabled \
 --public-access None \
 --tags $TAGS
echo "✅ PostgreSQL Flexible Server created: $PSQL_NAME"
# 2. Create database
echo ""
echo "📊 Creating application database..."
az postgres flexible-server db create \
 --resource-group "$RG_NAME" \
 --server-name "$PSQL_NAME" \
 --database-name "$DB_NAME"
echo "✅ Database created: $DB_NAME"
# 3. Get PostgreSQL Server ID
PSQL_ID=$(az postgres flexible-server show \
 --resource-group "$RG_NAME" \
 --name "$PSQL_NAME" \
 --query id -o tsv)
# 4. Create Private Endpoint
echo ""
echo "🔒 Creating Private Endpoint for PostgreSQL..."
az network private-endpoint create \
 --resource-group "$RG_NAME" \
 --name "$PE_NAME" \
 --location "$LOCATION" \
 --vnet-name "$VNET_NAME" \
 --subnet "$SUBNET_PE_NAME" \
 --private-connection-resource-id "$PSQL_ID" \
 --group-id postgresqlServer \
 --connection-name "${PSQL_NAME}-connection" \
 --tags $TAGS
echo "✅ Private Endpoint created: $PE_NAME"
# 5. Get Private Endpoint NIC Private IP
PE_NIC_ID=$(az network private-endpoint show \
 --resource-group "$RG_NAME" \
 --name "$PE_NAME" \
 --query 'networkInterfaces[0].id' -o tsv)
PRIVATE_IP=$(az network nic show --ids "$PE_NIC_ID" --query 'ipConfigurations[0].privateIPAddress' -o tsv)
echo " Private IP: $PRIVATE_IP"
# 6. Create Private DNS Zone Group (auto-registers A record)
echo ""
echo "🌐 Creating Private DNS Zone Group..."
az network private-endpoint dns-zone-group create \
 --resource-group "$RG_NAME" \
 --endpoint-name "$PE_NAME" \
 --name "default" \
 --private-dns-zone "$PRIVATE_DNS_ZONE" \
 --zone-name "postgres"
echo "✅ Private DNS Zone Group created (DNS auto-registered)"
# 7. Update Key Vault with actual database connection string
echo ""
echo "🔑 Updating Key Vault with database credentials..."
CONNECTION_STRING="postgresql://${DB_ADMIN_USER}:${DB_ADMIN_PASSWORD}@${PSQL_NAME}.postgres.database.azure.com/${DB_NAME}?sslmode=require"
az keyvault secret set \
 --vault-name "$KV_NAME" \
 --name "postgres-connection-string" \
 --value "$CONNECTION_STRING" \
 --description "PostgreSQL connection string for ${ENVIRONMENT} environment"
# Also store admin password separately (for emergency access)
az keyvault secret set \
 --vault-name "$KV_NAME" \
 --name "postgres-admin-password" \
 --value "$DB_ADMIN_PASSWORD" \
 --description "PostgreSQL admin password for ${ENVIRONMENT} environment"
echo "✅ Database credentials stored in Key Vault"
# 8. Configure PostgreSQL parameters
echo ""
echo "⚙️ Configuring PostgreSQL server parameters..."
# Set connection pooling (optional - requires PgBouncer extension)
# az postgres flexible-server parameter set \
# --resource-group "$RG_NAME" \
# --server-name "$PSQL_NAME" \
# --name "pgbouncer.enabled" \
# --value "true"
# Set SSL enforcement
az postgres flexible-server parameter set \
 --resource-group "$RG_NAME" \
 --server-name "$PSQL_NAME" \
 --name "require_secure_transport" \
 --value "on"
echo "✅ PostgreSQL parameters configured"
# Summary
echo ""
echo "=========================================="
echo "✅ Layer 4 Deployment Complete!"
echo "=========================================="
echo "Resources created:"
echo " - PostgreSQL Flexible Server: $PSQL_NAME"
echo " Version: PostgreSQL $DB_VERSION"
echo " SKU: $DATABASE_SKU (Burstable)"
echo " Storage: ${DB_STORAGE_SIZE_GB} GB"
echo " Backup Retention: ${DB_BACKUP_RETENTION_DAYS} days"
echo " High Availability: Disabled (dev)"
echo " Public Access: Disabled"
echo " - Database: $DB_NAME"
echo " - Private Endpoint: $PE_NAME"
echo " Private IP: $PRIVATE_IP"
echo " - DNS: Auto-registered in $PRIVATE_DNS_ZONE"
echo " - Key Vault Secrets:"
echo " ✓ postgres-connection-string (updated)"
echo " ✓ postgres-admin-password (new)"
echo "=========================================="
echo ""
echo "⚠️ Database Connection Details:"
echo " Host: ${PSQL_NAME}.postgres.database.azure.com"
echo " Port: 5432"
echo " Database: ${DB_NAME}"
echo " User: ${DB_ADMIN_USER}"
echo " SSL Mode: require"
echo ""
echo " Connection is only available via private endpoint within VNet"
echo " Container Apps will automatically use updated connection string from Key Vault"
echo ""
echo "Next step: Run ./05-deploy-monitoring.sh ${ENVIRONMENT}"
echo ""
