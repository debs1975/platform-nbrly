#!/bin/bash

# Source helper scripts
source ../helpers/logging.sh
source ../helpers/azure-login.sh

# Define the output file
output_file="../../config/.generated/generated-infra-dev.json"

# Variables from state file
rgName=$(jq -r '.common.resourceGroupName' "$output_file")
appgwName=$(jq -r '.common.appGatewayName' "$output_file")
certName=$(jq -r '.common.sslCertificateName' "$output_file")
caIpAddress=$(jq -r ".tenants.${tenantName}.containerAppIpAddress" "$output_file")
tenantHostName=$(jq -r ".tenants.${tenantName}.hostName" "$output_file")

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
        --servers "$caIpAddress"
else
    log_info "Creating backend pool: ${backendPoolName}"
    az network application-gateway address-pool create \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$backendPoolName" \
        --servers "$caIpAddress"
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
if az network application-gateway http-setting show \
    --gateway-name "$appgwName" \
    --resource-group "$rgName" \
    --name "$httpSettingName" >/dev/null 2>&1; then
    log_info "HTTP setting '${httpSettingName}' already exists, updating probe and host name."
    az network application-gateway http-setting update \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$httpSettingName" \
        --host-name "${tenantHostName}" \
        --probe "$probeName"
else
    log_info "Creating HTTP setting: ${httpSettingName}"
    az network application-gateway http-setting create \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$httpSettingName" \
        --port 80 \
        --protocol "Http" \
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
    az network application-gateway rule create \
        --gateway-name "$appgwName" \
        --resource-group "$rgName" \
        --name "$routingRuleName" \
        --http-listener "$httpListenerName" \
        --rule-type "Basic" \
        --address-pool "$backendPoolName" \
        --http-settings "$httpSettingName"
fi

log_info "Application Gateway routing configuration for '${tenantName}' complete."
log_info "You should be able to access the application at https://${tenantHostName}"
