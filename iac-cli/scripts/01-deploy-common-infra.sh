#!/bin/bash

# Source helper scripts
source ./helpers/logging.sh
source ./helpers/azure-login.sh

# Load common parameters
source <(jq -r 'to_entries | .[] | "export \(.key)=\(.value)"' ../config/parameters-dev.json)

# Define the output file for generated infrastructure details
output_file="../config/.generated/generated-infra-dev.json"

# Initialize the output file
log_info "Initializing generated infrastructure file: $output_file"
echo '{}' | jq '.common = {} | .tenants = {}' > "$output_file"

# Variables
rgName="${project}-${env}-${region}-rg"
vnetName="${project}-${env}-${region}-vnet"
agwName="${project}-${env}-${region}-agw"
pipName="${project}-${env}-${region}-pip"
kvName="${project}${env}${region}kv" # Key Vault names have restrictions
acrName="${project}${env}${region}acr" # ACR names have restrictions
lawName="${project}-${env}-${region}-law"
agwUamiName="agw-managed-identity" # Managed identity for the AGW

# Login to Azure
azure_login

# 1. Create Resource Group
log_info "Checking if resource group exists: $rgName"
if ! az group show --name "$rgName" &>/dev/null; then
    log_info "Creating resource group: $rgName"
    rgId=$(az group create --name "$rgName" --location "$region" --query "id" -o tsv)
else
    log_info "Resource group already exists: $rgName"
    rgId=$(az group show --name "$rgName" --query "id" -o tsv)
fi
jq --arg rgName "$rgName" --arg rgId "$rgId" \
   '.common.resourceGroupName = $rgName | .common.resourceGroupId = $rgId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# 2. Setup Networking
log_info "Checking if VNet exists: $vnetName"
if ! az network vnet show --name "$vnetName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating VNet: $vnetName"
    vnetId=$(az network vnet create \
      --name "$vnetName" \
      --resource-group "$rgName" \
      --location "$region" \
      --address-prefix "$vnetAddressPrefix" \
      --query "id" -o tsv)
else
    log_info "VNet already exists: $vnetName"
    vnetId=$(az network vnet show --name "$vnetName" --resource-group "$rgName" --query "id" -o tsv)
fi
jq --arg vnetName "$vnetName" --arg vnetId "$vnetId" \
   '.common.vnetName = $vnetName | .common.vnetId = $vnetId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

log_info "Checking if Application Gateway subnet exists"
if ! az network vnet subnet show --name "snet-appgateway" --vnet-name "$vnetName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Application Gateway subnet"
    az network vnet subnet create \
      --name "snet-appgateway" \
      --vnet-name "$vnetName" \
      --resource-group "$rgName" \
      --address-prefixes "$appGatewaySubnetPrefix"
else
    log_info "Application Gateway subnet already exists"
fi

log_info "Checking if Bastion subnet exists"
if ! az network vnet subnet show --name "AzureBastionSubnet" --vnet-name "$vnetName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Bastion subnet"
    az network vnet subnet create \
      --name "AzureBastionSubnet" \
      --vnet-name "$vnetName" \
      --resource-group "$rgName" \
      --address-prefixes "$bastionSubnetPrefix"
else
    log_info "Bastion subnet already exists"
fi

log_info "Checking if PostgreSQL subnet exists"
if ! az network vnet subnet show --name "snet-postgres" --vnet-name "$vnetName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating PostgreSQL subnet"
    az network vnet subnet create \
      --name "snet-postgres" \
      --vnet-name "$vnetName" \
      --resource-group "$rgName" \
      --address-prefixes "$postgresSubnetPrefix" \
      --delegations "Microsoft.DBforPostgreSQL/flexibleServers"
else
    log_info "PostgreSQL subnet already exists"
fi

# 3. Deploy Core Services
log_info "Checking if Log Analytics Workspace exists: $lawName"
if ! az monitor log-analytics workspace show --resource-group "$rgName" --workspace-name "$lawName" &>/dev/null; then
    log_info "Creating Log Analytics Workspace: $lawName"
    lawOutput=$(az monitor log-analytics workspace create \
      --resource-group "$rgName" \
      --workspace-name "$lawName" \
      --location "$region")
    lawId=$(echo "$lawOutput" | jq -r '.id')
    lawCustomerId=$(echo "$lawOutput" | jq -r '.customerId')
else
    log_info "Log Analytics Workspace already exists: $lawName"
    lawOutput=$(az monitor log-analytics workspace show --resource-group "$rgName" --workspace-name "$lawName")
    lawId=$(echo "$lawOutput" | jq -r '.id')
    lawCustomerId=$(echo "$lawOutput" | jq -r '.customerId')
fi
jq --arg lawName "$lawName" --arg lawId "$lawId" --arg lawCustomerId "$lawCustomerId" \
   '.common.logAnalyticsWorkspaceName = $lawName | .common.logAnalyticsWorkspaceId = $lawId | .common.logAnalyticsCustomerId = $lawCustomerId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

log_info "Checking if Azure Container Registry exists: $acrName"
if ! az acr show --name "$acrName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Azure Container Registry: $acrName"
    acrId=$(az acr create \
      --resource-group "$rgName" \
      --name "$acrName" \
      --sku "Standard" \
      --admin-enabled false \
      --query "id" -o tsv)
else
    log_info "Azure Container Registry already exists: $acrName"
    acrId=$(az acr show --name "$acrName" --resource-group "$rgName" --query "id" -o tsv)
fi
jq --arg acrName "$acrName" --arg acrId "$acrId" \
   '.common.acrName = $acrName | .common.acrId = $acrId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

log_info "Checking if Key Vault exists: $kvName"
if ! az keyvault show --name "$kvName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Key Vault: $kvName"
    kvId=$(az keyvault create \
      --name "$kvName" \
      --resource-group "$rgName" \
      --location "$region" \
      --enable-rbac-authorization true \
      --query "id" -o tsv)
else
    log_info "Key Vault already exists: $kvName"
    kvId=$(az keyvault show --name "$kvName" --resource-group "$rgName" --query "id" -o tsv)
fi
jq --arg kvName "$kvName" --arg kvId "$kvId" \
   '.common.keyVaultName = $kvName | .common.keyVaultId = $kvId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# 4. Upload Certificate to Key Vault
certName=$(jq -r '.customDomain.certificateName' ../config/parameters-dev.json | tr -d ' ') # remove whitespace
log_info "Checking if SSL certificate exists in Key Vault: $certName"
if ! az keyvault certificate show --vault-name "$kvName" --name "$certName" &>/dev/null; then
    log_info "Importing SSL certificate to Key Vault"
    certPassword=$(jq -r '.certificatePassword' ../creds/astrapiaio.json)
    certFilePath=$(jq -r '.customDomain.certificateFilePath' ../config/parameters-dev.json)
    
    certId=$(az keyvault certificate import \
      --vault-name "$kvName" \
      --name "$certName" \
      --file "$certFilePath" \
      --password "$certPassword" \
      --query "id" -o tsv)
else
    log_info "SSL certificate already exists in Key Vault: $certName"
    certId=$(az keyvault certificate show --vault-name "$kvName" --name "$certName" --query "id" -o tsv)
fi

jq --arg certName "$certName" --arg certId "$certId" \
   '.common.sslCertificateName = $certName | .common.sslCertificateId = $certId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# 5. Deploy Application Gateway
log_info "Checking if Public IP exists: $pipName"
if ! az network public-ip show --name "$pipName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Public IP for Application Gateway"
    pipId=$(az network public-ip create \
      --name "$pipName" \
      --resource-group "$rgName" \
      --allocation-method "Static" \
      --sku "Standard" \
      --query "id" -o tsv)
else
    log_info "Public IP already exists: $pipName"
    pipId=$(az network public-ip show --name "$pipName" --resource-group "$rgName" --query "id" -o tsv)
fi
pipAddress=$(az network public-ip show --ids "$pipId" --query "ipAddress" -o tsv)
jq --arg pipName "$pipName" --arg pipId "$pipId" --arg pipAddress "$pipAddress" \
    '.common.appGatewayPublicIpName = $pipName | .common.appGatewayPublicIpId = $pipId | .common.appGatewayPublicIpAddress = $pipAddress' \
    "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

log_info "Checking if Managed Identity exists: $agwUamiName"
if ! az identity show --name "$agwUamiName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Managed Identity for Application Gateway: $agwUamiName"
    agwUamiId=$(az identity create --name "$agwUamiName" --resource-group "$rgName" --query "id" -o tsv)
else
    log_info "Managed Identity already exists: $agwUamiName"
    agwUamiId=$(az identity show --name "$agwUamiName" --resource-group "$rgName" --query "id" -o tsv)
fi
agwUamiPrincipalId=$(az identity show --name "$agwUamiName" --resource-group "$rgName" --query "principalId" -o tsv)
jq --arg uamiName "$agwUamiName" --arg uamiId "$agwUamiId" \
    '.common.appGatewayManagedIdentityName = $uamiName | .common.appGatewayManagedIdentityId = $uamiId' \
    "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

log_info "Setting Key Vault access policy for Application Gateway Identity"
az keyvault set-policy \
  --name "$kvName" \
  --resource-group "$rgName" \
  --object-id "$agwUamiPrincipalId" \
  --secret-permissions get list \
  --certificate-permissions get list

log_info "Checking if Application Gateway exists: $agwName"
if ! az network application-gateway show --name "$agwName" --resource-group "$rgName" &>/dev/null; then
    log_info "Deploying Application Gateway: $agwName"
    agwId=$(az network application-gateway create \
      --name "$agwName" \
      --resource-group "$rgName" \
      --location "$region" \
      --sku "WAF_v2" \
      --public-ip-address "$pipName" \
      --vnet-name "$vnetName" \
      --subnet "snet-appgateway" \
      --identity "$agwUamiId" \
      --query "id" -o tsv)
else
    log_info "Application Gateway already exists: $agwName"
    agwId=$(az network application-gateway show --name "$agwName" --resource-group "$rgName" --query "id" -o tsv)
fi
jq --arg agwName "$agwName" --arg agwId "$agwId" \
   '.common.appGatewayName = $agwName | .common.appGatewayId = $agwId' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"

# 6. Configure Application Gateway with SSL Certificate
log_info "Adding SSL certificate from Key Vault to Application Gateway"
certId=$(jq -r '.common.sslCertificateId' "$output_file")
certName=$(jq -r '.common.sslCertificateName' "$output_file")

log_info "Checking if SSL certificate '$certName' is already added to Application Gateway"
if ! az network application-gateway ssl-cert show --gateway-name "$agwName" --resource-group "$rgName" --name "$certName" &>/dev/null; then
    log_info "Adding SSL certificate '$certName' to Application Gateway"
    az network application-gateway ssl-cert create \
        --gateway-name "$agwName" \
        --resource-group "$rgName" \
        --name "$certName" \
        --key-vault-secret-id "$certId"
else
    log_info "SSL certificate '$certName' is already added to Application Gateway"
fi

# Create frontend port for HTTPS
log_info "Checking if HTTPS frontend port 'port_443' exists"
if ! az network application-gateway frontend-port show --gateway-name "$agwName" --resource-group "$rgName" --name "port_443" &>/dev/null; then
    log_info "Creating HTTPS frontend port on Application Gateway"
    az network application-gateway frontend-port create \
        --gateway-name "$agwName" \
        --resource-group "$rgName" \
        --name "port_443" \
        --port 443
else
    log_info "HTTPS frontend port 'port_443' already exists"
fi

log_info "Common infrastructure deployment complete."
log_info "Next step: Run 02-deploy-tenant-infra.sh for each tenant."
