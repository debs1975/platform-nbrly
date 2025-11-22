#!/bin/bash

# Usage: ./04-configure-routing.sh <tenant> <project> [environment]
# Example: ./04-configure-routing.sh nbrly astra dev
# Example: ./04-configure-routing.sh bloom astra dev

# Exit immediately if a command exits with a non-zero status
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper scripts
source "${SCRIPT_DIR}/helpers/logging.sh"
source "${SCRIPT_DIR}/helpers/azure-login.sh"

# Trap errors and print error message
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

# Get tenant name parameter (required)
TENANT=${1}
if [ -z "$TENANT" ]; then
  log_error "Tenant name is required"
  log_error "Usage: ./04-configure-routing.sh <tenant> <project> [dev|stage|prod]"
  log_error "Example: ./04-configure-routing.sh nbrly astra dev"
  exit 1
fi

# Get project name parameter (required)
PROJECT=${2}
if [ -z "$PROJECT" ]; then
  log_error "Project name is required"
  log_error "Usage: ./04-configure-routing.sh <tenant> <project> [dev|stage|prod]"
  log_error "Example: ./04-configure-routing.sh nbrly astra dev"
  exit 1
fi

# Get environment parameter (default to dev if not provided)
ENV=${3:-dev}

# Validate environment
if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
  log_error "Invalid environment: $ENV"
  log_error "Usage: ./04-configure-routing.sh <tenant> <project> [dev|stage|prod]"
  exit 1
fi

# Validate tenant
if [[ ! "$TENANT" =~ ^(nbrly|bloom)$ ]]; then
  log_error "Invalid tenant: $TENANT (must be 'nbrly' or 'bloom')"
  exit 1
fi

log_info "Configuring ${TENANT} routing for project: $PROJECT, environment: $ENV"

# Load tenant config to get tenantName
TENANT_CONFIG="${SCRIPT_DIR}/../config/${TENANT}/parameters-${ENV}.json"
if [ ! -f "$TENANT_CONFIG" ]; then
  log_error "Tenant configuration file not found: $TENANT_CONFIG"
  exit 1
fi

tenantName=$(jq -r '.tenantName' "$TENANT_CONFIG")

# Define the output file
output_file="${SCRIPT_DIR}/../config/.generated/generated-infra-${ENV}.json"
infra_file="${SCRIPT_DIR}/../config/infra-${ENV}.json"

# Create backups of state files at the start
timestamp=$(date +"%Y%m%d-%H%M%S")
backup_dir_generated="${SCRIPT_DIR}/../config/.generated/.bak"
backup_dir_config="${SCRIPT_DIR}/../config/.bak"
mkdir -p "$backup_dir_generated" "$backup_dir_config"

if [ -f "$output_file" ]; then
  backup_file="${backup_dir_generated}/$(basename "$output_file").backup-${timestamp}"
  cp "$output_file" "$backup_file"
  log_info "Created backup: $backup_file"
fi

if [ -f "$infra_file" ]; then
  backup_file="${backup_dir_config}/$(basename "$infra_file").backup-${timestamp}"
  cp "$infra_file" "$backup_file"
  log_info "Created backup: $backup_file"
fi

# Variables from state file
rgName=$(jq -r '.common.resourceGroupName' "$output_file")
appgwName=$(jq -r '.common.appGatewayName' "$output_file")
certName=$(jq -r '.common.sslCertificateName' "$output_file")
caeStaticIp=$(jq -r ".tenants.${tenantName}.containerAppEnvStaticIp // empty" "$output_file")
tenantHostName=$(jq -r ".tenants.${tenantName}.hostName" "$output_file")

# Check if Container App Environment has been deployed
if [ -z "$caeStaticIp" ] || [ "$caeStaticIp" == "null" ]; then
  log_error "Container App Environment not deployed for tenant: $tenantName"
  log_error "Please run: ./03-deploy-tenant-resources.sh ${TENANT} ${PROJECT} ${ENV}"
  exit 1
fi

log_info "Using Container App Environment static IP: $caeStaticIp"

# Variables for this script
backendPoolName="${tenantName}-bp"
httpListenerName="${tenantName}-hl"
probeName="${tenantName}-probe"
routingRuleName="${tenantName}-rr"
httpSettingName="${tenantName}-http"

# Login to Azure
azure_login

# Configure Application Gateway for the tenant
log_info "Configuring Application Gateway for tenant: ${tenantName}"

# 1. Create Backend Pool
log_info "Checking if backend pool exists: ${backendPoolName}"
if az network application-gateway address-pool show \
    --gateway-name "$appgwName" \
    --resource-group "$rgName" \
    --name "$backendPoolName" >/dev/null 2>&1; then
    log_info "Backend pool '${backendPoolName}' already exists, updating servers."
    az network application-gateway address-pool update \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$backendPoolName" \
        --servers "$caeStaticIp"
else
    log_info "Creating backend pool: ${backendPoolName}"
    az network application-gateway address-pool create \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$backendPoolName" \
        --servers "$caeStaticIp"
fi

# 2. Create Health Probe
log_info "Checking if health probe exists: ${probeName}"
if az network application-gateway probe show \
    --gateway-name "$appgwName" \
    --resource-group "$rgName" \
    --name "$probeName" >/dev/null 2>&1; then
    log_info "Health probe '${probeName}' already exists, updating protocol and host."
    az network application-gateway probe update \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$probeName" \
        --protocol "Https" \
        --host "${tenantHostName}" \
        --path "/"
else
    log_info "Creating health probe: ${probeName}"
    az network application-gateway probe create \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$probeName" \
        --protocol "Https" \
        --host "${tenantHostName}" \
        --path "/" \
        --interval 30 \
        --timeout 30 \
        --threshold 3
fi

# 3. Create HTTP Setting
log_info "Checking if HTTP setting exists: ${httpSettingName}"
if az network application-gateway http-settings show \
    --gateway-name "$appgwName" \
    --resource-group "$rgName" \
    --name "$httpSettingName" >/dev/null 2>&1; then
    log_info "HTTP setting '${httpSettingName}' already exists, updating probe and host name."
    az network application-gateway http-settings update \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$httpSettingName" \
        --host-name "${tenantHostName}" \
        --probe "$probeName"
else
    log_info "Creating HTTP setting: ${httpSettingName}"
    az network application-gateway http-settings create \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$httpSettingName" \
        --port 443 \
        --protocol "Https" \
        --probe "$probeName" \
        --host-name "${tenantHostName}"
fi

# 4. Create Frontend Listener
log_info "Checking if HTTPS listener exists: ${httpListenerName}"
if az network application-gateway http-listener show \
    --gateway-name "$appgwName" \
    --resource-group "$rgName" \
    --name "$httpListenerName" >/dev/null 2>&1; then
    log_info "HTTPS listener '${httpListenerName}' already exists, updating."
    az network application-gateway http-listener update \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$httpListenerName" \
        --frontend-port "port_443" \
        --host-name "${tenantHostName}" \
        --ssl-cert "$certName"
else
    log_info "Creating HTTPS listener: ${httpListenerName}"
    az network application-gateway http-listener create \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$httpListenerName" \
        --frontend-port "port_443" \
        --host-name "${tenantHostName}" \
        --ssl-cert "$certName"
fi

# 5. Create Routing Rule
log_info "Checking if routing rule exists: ${routingRuleName}"
if az network application-gateway rule show \
    --gateway-name "$appgwName" \
    --resource-group "$rgName" \
    --name "$routingRuleName" >/dev/null 2>&1; then
    log_info "Routing rule '${routingRuleName}' already exists, skipping creation"
else
    log_info "Creating routing rule: ${routingRuleName}"
    
    # Get existing priorities and find next available one
    existing_priorities=$(az network application-gateway rule list \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --query "[].priority" -o tsv 2>/dev/null | sort -n)
    
    # Calculate priority based on tenant name with offset to avoid conflicts
    case "$tenantName" in
        "nbrly") base_priority=1000 ;;
        "bloom") base_priority=2000 ;;
        *) base_priority=5000 ;;
    esac
    
    # Find next available priority starting from base
    priority=$base_priority
    while echo "$existing_priorities" | grep -q "^${priority}$"; do
        priority=$((priority + 10))
    done
    
    log_info "Using priority: $priority"
    
    az network application-gateway rule create \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$routingRuleName" \
        --http-listener "$httpListenerName" \
        --rule-type "Basic" \
        --address-pool "$backendPoolName" \
        --http-settings "$httpSettingName" \
        --priority $priority
fi

# Save Application Gateway routing configuration to state files
log_info "Saving Application Gateway routing configuration to state files..."

# Update generated-infra with routing details
jq --arg tenant "$tenantName" \
   --arg backendPool "$backendPoolName" \
   --arg probe "$probeName" \
   --arg httpSetting "$httpSettingName" \
   --arg listener "$httpListenerName" \
   --arg rule "$routingRuleName" \
   --arg staticIp "$caeStaticIp" \
   '.tenants[$tenant] += {
     appGateway: {
       backendPoolName: $backendPool,
       backendPoolIp: $staticIp,
       healthProbeName: $probe,
       httpSettingName: $httpSetting,
       httpListenerName: $listener,
       routingRuleName: $rule
     }
   }' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# Update infra tracking file with routing details
jq --arg tenant "$tenantName" \
   --arg backendPool "$backendPoolName" \
   --arg probe "$probeName" \
   --arg httpSetting "$httpSettingName" \
   --arg listener "$httpListenerName" \
   --arg rule "$routingRuleName" \
   --arg staticIp "$caeStaticIp" \
   '.resources.tenants //= {} | .resources.tenants[$tenant] += {
     appGateway: {
       backendPoolName: $backendPool,
       backendPoolIp: $staticIp,
       healthProbeName: $probe,
       httpSettingName: $httpSetting,
       httpListenerName: $listener,
       routingRuleName: $rule
     }
   }' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

log_success "Application Gateway routing configuration saved to state files"

log_info "Application Gateway routing configuration for '${tenantName}' complete."
log_info "You should be able to access the application at https://${tenantHostName}"
