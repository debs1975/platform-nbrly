#!/bin/bash

# Source helper scripts
source ../helpers/logging.sh
source ../helpers/azure-login.sh

# Load common and tenant parameters
source <(jq -r 'to_entries | .[] | "export \(.key)=\(.value)"' ../../config/parameters-dev.json)
source <(jq -r 'to_entries | .[] | "export \(.key)=\(.value)"' ../../config/nbrly/parameters-dev.json)

# Define the output file
output_file="../../config/.generated/generated-infra-dev.json"

# Variables
rgName=$(jq -r '.common.resourceGroupName' "$output_file")
vnetName=$(jq -r '.common.vnetName' "$output_file")
kvName=$(jq -r '.common.keyVaultName' "$output_file")
acrName=$(jq -r '.common.acrName' "$output_file")
lawId=$(jq -r '.common.logAnalyticsWorkspaceId' "$output_file")

caeSubnetName="snet-${tenantName}-${env}-cae"
caeName="${tenantName}-${env}-cae"
uamiName="${tenantName}-${env}-uami"
psqlName="${tenantName}-${env}-psql"
caName="${tenantName}-${env}-app1-ca"

# Login to Azure
azure_login

# 1. Create Tenant Subnet
log_info "Checking if subnet ${caeSubnetName} exists..."
subnetId=$(az network vnet subnet show \
    --name "$caeSubnetName" \
    --vnet-name "$vnetName" \
    --resource-group "$rgName" \
    --query "id" -o tsv 2>/dev/null)

if [ -z "$subnetId" ]; then
    log_info "Creating subnet for tenant ${tenantName}: ${caeSubnetName}"
    subnetId=$(az network vnet subnet create \
        --name "$caeSubnetName" \
        --vnet-name "$vnetName" \
        --resource-group "$rgName" \
        --address-prefixes "$caeSubnetPrefix" \
        --delegations "Microsoft.App/environments" \
        --query "id" -o tsv)
else
    log_info "Subnet ${caeSubnetName} already exists"
fi

jq --arg tenant "$tenantName" --arg subnetName "$caeSubnetName" --arg subnetId "$subnetId" \
   '.tenants[$tenant].subnetName = $subnetName | .tenants[$tenant].subnetId = $subnetId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# 2. Create User-Assigned Managed Identity
log_info "Checking if User-Assigned Managed Identity ${uamiName} exists..."
uamiId=$(az identity show --name "$uamiName" --resource-group "$rgName" --query "id" -o tsv 2>/dev/null)

if [ -z "$uamiId" ]; then
    log_info "Creating User-Assigned Managed Identity: ${uamiName}"
    uamiId=$(az identity create --name "$uamiName" --resource-group "$rgName" --query "id" -o tsv)
else
    log_info "User-Assigned Managed Identity ${uamiName} already exists"
fi

uamiPrincipalId=$(az identity show --name "$uamiName" --resource-group "$rgName" --query "principalId" -o tsv)
jq --arg tenant "$tenantName" --arg uamiName "$uamiName" --arg uamiId "$uamiId" \
   '.tenants[$tenant].managedIdentityName = $uamiName | .tenants[$tenant].managedIdentityId = $uamiId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# Check if AcrPull role assignment exists
log_info "Checking if UAMI has AcrPull role on ACR..."
acrId=$(jq -r '.common.acrId' "$output_file")
roleAssignment=$(az role assignment list \
    --assignee "$uamiPrincipalId" \
    --role "AcrPull" \
    --scope "$acrId" \
    --query "[0].id" -o tsv 2>/dev/null)

if [ -z "$roleAssignment" ]; then
    log_info "Granting UAMI AcrPull role on ACR"
    az role assignment create \
        --assignee "$uamiPrincipalId" \
        --role "AcrPull" \
        --scope "$acrId"
else
    log_info "UAMI already has AcrPull role on ACR"
fi

# 3. Deploy PostgreSQL Database
log_info "Checking if PostgreSQL server ${psqlName} exists..."
psqlId=$(az postgres flexible-server show --name "$psqlName" --resource-group "$rgName" --query "id" -o tsv 2>/dev/null)

if [ -z "$psqlId" ]; then
    log_info "Deploying PostgreSQL server: ${psqlName}"
    psqlOutput=$(az postgres flexible-server create \
        --name "$psqlName" \
        --resource-group "$rgName" \
        --location "$region" \
        --admin-user "psqladmin" \
        --admin-password "yourStrongPassword123!" \
        --subnet "$subnetId" \
        --yes)
    psqlId=$(echo "$psqlOutput" | jq -r '.id')
    psqlConnectionString=$(echo "$psqlOutput" | jq -r '.connectionString')
    
    log_info "Storing PostgreSQL connection string in Key Vault"
    az keyvault secret set \
        --vault-name "$kvName" \
        --name "${psqlName}-connection-string" \
        --value "$psqlConnectionString"
else
    log_info "PostgreSQL server ${psqlName} already exists"
fi

jq --arg tenant "$tenantName" --arg psqlName "$psqlName" --arg psqlId "$psqlId" \
   '.tenants[$tenant].postgresServerName = $psqlName | .tenants[$tenant].postgresServerId = $psqlId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# 4. Deploy Container App Environment
log_info "Checking if Container App Environment ${caeName} exists..."
caeId=$(az containerapp env show --name "$caeName" --resource-group "$rgName" --query "id" -o tsv 2>/dev/null)

if [ -z "$caeId" ]; then
    log_info "Creating Container App Environment: ${caeName}"
    caeId=$(az containerapp env create \
        --name "$caeName" \
        --resource-group "$rgName" \
        --location "$region" \
        --logs-workspace-id "$lawId" \
        --infrastructure-subnet-resource-id "$subnetId" \
        --internal-only true \
        --query "id" -o tsv)
else
    log_info "Container App Environment ${caeName} already exists"
fi

jq --arg tenant "$tenantName" --arg caeName "$caeName" --arg caeId "$caeId" \
   '.tenants[$tenant].containerAppEnvName = $caeName | .tenants[$tenant].containerAppEnvId = $caeId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# 5. Deploy Container App
log_info "Checking if Container App ${caName} exists..."
caId=$(az containerapp show --name "$caName" --resource-group "$rgName" --query "id" -o tsv 2>/dev/null)

if [ -z "$caId" ]; then
    log_info "Deploying Container App: ${caName}"
    caOutput=$(az containerapp create \
        --name "$caName" \
        --resource-group "$rgName" \
        --environment "$caeName" \
        --image "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest" \
        --user-assigned "$uamiId" \
        --registry-server "$(jq -r '.common.acrName' "$output_file").azurecr.io" \
        --target-port 80 \
        --ingress "internal" \
        --secrets "psql-conn-string=${psqlName}-connection-string")
    caId=$(echo "$caOutput" | jq -r '.id')
    caIp=$(echo "$caOutput" | jq -r '.properties.configuration.ingress.fqdn')
else
    log_info "Container App ${caName} already exists"
    caIp=$(az containerapp show --name "$caName" --resource-group "$rgName" --query "properties.configuration.ingress.fqdn" -o tsv)
fi

jq --arg tenant "$tenantName" --arg caName "$caName" --arg caId "$caId" --arg caIp "$caIp" \
   '.tenants[$tenant].containerAppName = $caName | .tenants[$tenant].containerAppId = $caId | .tenants[$tenant].containerAppIpAddress = $caIp' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

log_info "Tenant resources deployment for '${tenantName}' complete."
log_info "Next step: Configure Application Gateway routing."
