#!/bin/bash

# Usage: ./01-deploy-tenant-resources.sh <project> [environment]
# Example: ./01-deploy-tenant-resources.sh astra dev

# Exit immediately if a command exits with a non-zero status
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper scripts
source "${SCRIPT_DIR}/../helpers/logging.sh"
source "${SCRIPT_DIR}/../helpers/azure-login.sh"

# Get project name parameter (required)
PROJECT=${1}
if [ -z "$PROJECT" ]; then
  log_error "Project name is required"
  log_error "Usage: ./01-deploy-tenant-resources.sh <project> [dev|stage|prod]"
  exit 1
fi

# Get environment parameter (default to dev if not provided)
ENV=${2:-dev}

# Validate environment
if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
  log_error "Invalid environment: $ENV"
  log_error "Usage: ./01-deploy-tenant-resources.sh <project> [dev|stage|prod]"
  exit 1
fi

log_info "Deploying NBRLY tenant resources for project: $PROJECT, environment: $ENV"

# Load common and tenant parameters
COMMON_CONFIG="${SCRIPT_DIR}/../../config/parameters-${ENV}.json"
TENANT_CONFIG="${SCRIPT_DIR}/../../config/nbrly/parameters-${ENV}.json"

if [ ! -f "$COMMON_CONFIG" ]; then
  log_error "Common configuration file not found: $COMMON_CONFIG"
  exit 1
fi

if [ ! -f "$TENANT_CONFIG" ]; then
  log_error "Tenant configuration file not found: $TENANT_CONFIG"
  exit 1
fi

# Load top-level scalar values from configs (skip nested objects)
while IFS="=" read -r key value; do
  export "$key"="$value"
done < <(jq -r 'to_entries | .[] | select(.value | type != "object") | "\(.key)=\(.value)"' "$COMMON_CONFIG")

while IFS="=" read -r key value; do
  export "$key"="$value"
done < <(jq -r 'to_entries | .[] | select(.value | type != "object") | "\(.key)=\(.value)"' "$TENANT_CONFIG")

# Override project and env variables with parameters (takes precedence)
project="$PROJECT"
env="$ENV"
region="${region:-eastus}"

log_info "Loaded configuration - Tenant: $tenantName, Project: $project, Environment: $env"

# Define the output files
output_file="${SCRIPT_DIR}/../../config/.generated/generated-infra-${ENV}.json"
infra_file="${SCRIPT_DIR}/../../config/infra-${ENV}.json"

# Variables
rgName=$(jq -r '.common.resourceGroupName' "$output_file")
vnetName=$(jq -r '.common.vnetName' "$output_file")
kvName=$(jq -r '.common.keyVaultName' "$output_file")
acrName=$(jq -r '.common.acrName' "$output_file")
lawId=$(jq -r '.common.logAnalyticsWorkspaceId' "$output_file")

# Derive tenant resource names from project, tenant, and environment
caeSubnetName="snet-${tenantName}-${env}-cae"
caeName="${tenantName}-${env}-cae"
uamiName="${tenantName}-${env}-uami"
psqlName="${tenantName}-${env}-psql"
caName="${tenantName}-${env}-app1-ca"

# Print all inferred variables before deployment
log_info "======================================================"
log_info "Inferred Tenant Resource Names (${tenantName}):"
log_info "======================================================"
log_info "Project:              $project"
log_info "Tenant:               $tenantName"
log_info "Environment:          $env"
log_info "Region:               $region"
log_info "CAE Subnet:           $caeSubnetName"
log_info "CAE Subnet Prefix:    $caeSubnetPrefix"
log_info "Container App Env:    $caeName"
log_info "Managed Identity:     $uamiName"
log_info "PostgreSQL Server:    $psqlName"
log_info "Container App:        $caName"
log_info "Domain Name:          $domainName"
log_info "======================================================"

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
    log_success "Created subnet: ${caeSubnetName}"
else
    log_info "Subnet ${caeSubnetName} already exists"
fi

jq --arg tenant "$tenantName" --arg subnetName "$caeSubnetName" --arg subnetId "$subnetId" --arg subnetPrefix "$caeSubnetPrefix" --arg hostName "$domainName" \
   '.tenants[$tenant].subnetName = $subnetName | .tenants[$tenant].subnetId = $subnetId | .tenants[$tenant].subnetPrefix = $subnetPrefix | .tenants[$tenant].hostName = $hostName' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg tenant "$tenantName" --arg subnetName "$caeSubnetName" --arg subnetId "$subnetId" --arg subnetPrefix "$caeSubnetPrefix" --arg hostName "$domainName" \
   '.resources.tenants[$tenant].subnet = {name: $subnetName, id: $subnetId, addressPrefix: $subnetPrefix} | .resources.tenants[$tenant].hostName = $hostName' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

# 2. Create User-Assigned Managed Identity
log_info "Checking if User-Assigned Managed Identity ${uamiName} exists..."
uamiId=$(az identity show --name "$uamiName" --resource-group "$rgName" --query "id" -o tsv 2>/dev/null)

uamiCreated=false
if [ -z "$uamiId" ]; then
    log_info "Creating User-Assigned Managed Identity: ${uamiName}"
    uamiId=$(az identity create --name "$uamiName" --resource-group "$rgName" --query "id" -o tsv)
    uamiCreated=true
    log_success "Created Managed Identity: ${uamiName}"
else
    log_info "User-Assigned Managed Identity ${uamiName} already exists"
fi

uamiPrincipalId=$(az identity show --name "$uamiName" --resource-group "$rgName" --query "principalId" -o tsv)

# If UAMI was just created, wait for Azure AD replication
if [ "$uamiCreated" = true ]; then
    log_info "Waiting 15 seconds for Managed Identity replication to Azure AD..."
    sleep 15
fi
jq --arg tenant "$tenantName" --arg uamiName "$uamiName" --arg uamiId "$uamiId" \
   '.tenants[$tenant].managedIdentityName = $uamiName | .tenants[$tenant].managedIdentityId = $uamiId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg tenant "$tenantName" --arg uamiName "$uamiName" --arg uamiId "$uamiId" \
   '.resources.tenants[$tenant].managedIdentity = {name: $uamiName, id: $uamiId}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

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
        --assignee-object-id "$uamiPrincipalId" \
        --assignee-principal-type "ServicePrincipal" \
        --role "AcrPull" \
        --scope "$acrId"
    log_success "Assigned AcrPull role to UAMI"
else
    log_info "UAMI already has AcrPull role on ACR"
fi

# Assign Key Vault Secrets User role to UAMI for reading secrets
log_info "Checking if UAMI has Key Vault Secrets User role..."
kvId=$(jq -r '.common.keyVaultId' "$output_file")
kvSecretsRole=$(az role assignment list \
    --assignee "$uamiPrincipalId" \
    --role "Key Vault Secrets User" \
    --scope "$kvId" \
    --query "[0].id" -o tsv 2>/dev/null || true)

if [ -z "$kvSecretsRole" ]; then
    log_info "Granting UAMI 'Key Vault Secrets User' role"
    az role assignment create \
        --assignee-object-id "$uamiPrincipalId" \
        --assignee-principal-type "ServicePrincipal" \
        --role "Key Vault Secrets User" \
        --scope "$kvId"
    log_success "Assigned 'Key Vault Secrets User' role to UAMI"
else
    log_info "UAMI already has 'Key Vault Secrets User' role"
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
    log_success "Created PostgreSQL server: ${psqlName}"
else
    log_info "PostgreSQL server ${psqlName} already exists"
    psqlId=$(az postgres flexible-server show --name "$psqlName" --resource-group "$rgName" --query "id" -o tsv)
fi

jq --arg tenant "$tenantName" --arg psqlName "$psqlName" --arg psqlId "$psqlId" \
   '.tenants[$tenant].postgresServerName = $psqlName | .tenants[$tenant].postgresServerId = $psqlId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg tenant "$tenantName" --arg psqlName "$psqlName" --arg psqlId "$psqlId" \
   '.resources.tenants[$tenant].postgresServer = {name: $psqlName, id: $psqlId}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

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
    log_success "Created Container App Environment: ${caeName}"
else
    log_info "Container App Environment ${caeName} already exists"
fi

jq --arg tenant "$tenantName" --arg caeName "$caeName" --arg caeId "$caeId" \
   '.tenants[$tenant].containerAppEnvName = $caeName | .tenants[$tenant].containerAppEnvId = $caeId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg tenant "$tenantName" --arg caeName "$caeName" --arg caeId "$caeId" \
   '.resources.tenants[$tenant].containerAppEnv = {name: $caeName, id: $caeId}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

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
    log_success "Created Container App: ${caName}"
else
    log_info "Container App ${caName} already exists"
    caIp=$(az containerapp show --name "$caName" --resource-group "$rgName" --query "properties.configuration.ingress.fqdn" -o tsv)
fi

jq --arg tenant "$tenantName" --arg caName "$caName" --arg caId "$caId" --arg caIp "$caIp" \
   '.tenants[$tenant].containerAppName = $caName | .tenants[$tenant].containerAppId = $caId | .tenants[$tenant].containerAppIpAddress = $caIp' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg tenant "$tenantName" --arg caName "$caName" --arg caId "$caId" --arg caIp "$caIp" \
   '.resources.tenants[$tenant].containerApp = {name: $caName, id: $caId, fqdn: $caIp}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

log_info "Tenant resources deployment for '${tenantName}' complete."
log_info "Next step: Configure Application Gateway routing."
