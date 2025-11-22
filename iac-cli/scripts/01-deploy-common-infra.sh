#!/bin/bash

# Usage: ./01-deploy-common-infra.sh <project> [environment]
# Example: ./01-deploy-common-infra.sh astra dev

# Exit immediately if a command exits with a non-zero status
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper scripts
source "${SCRIPT_DIR}/helpers/logging.sh"
source "${SCRIPT_DIR}/helpers/azure-login.sh"

# Trap errors and print error message
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

# Get project name parameter (required)
PROJECT=${1}
if [ -z "$PROJECT" ]; then
  log_error "Project name is required"
  log_error "Usage: ./01-deploy-common-infra.sh <project> [dev|stage|prod]"
  exit 1
fi

# Get environment parameter (default to dev if not provided)
ENV=${2:-dev}

# Validate environment
if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
  log_error "Invalid environment: $ENV"
  log_error "Usage: ./01-deploy-common-infra.sh <project> [dev|stage|prod]"
  exit 1
fi

log_info "Deploying common infrastructure for project: $PROJECT, environment: $ENV"

# Load common parameters
CONFIG_FILE="${SCRIPT_DIR}/../config/parameters-${ENV}.json"
if [ ! -f "$CONFIG_FILE" ]; then
  log_error "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# Load top-level scalar values from config (skip nested objects)
while IFS="=" read -r key value; do
  export "$key"="$value"
done < <(jq -r 'to_entries | .[] | select(.value | type != "object") | "\(.key)=\(.value)"' "$CONFIG_FILE")

# Override project from parameter (takes precedence over config file)
project="$PROJECT"
region="${region:-eastus}"

# Define the output file for generated infrastructure details
output_file="${SCRIPT_DIR}/../config/.generated/generated-infra-${ENV}.json"
infra_file="${SCRIPT_DIR}/../config/infra-${ENV}.json"

# Create backup directories if they don't exist
mkdir -p "${SCRIPT_DIR}/../config/.generated/.bak"
mkdir -p "${SCRIPT_DIR}/../config/.bak"

# Backup existing files if they exist
if [ -f "$output_file" ]; then
    backup_file="${SCRIPT_DIR}/../config/.generated/.bak/generated-infra-${ENV}.json.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backing up existing generated infrastructure file to: $backup_file"
    cp "$output_file" "$backup_file"
fi

if [ -f "$infra_file" ]; then
    backup_infra_file="${SCRIPT_DIR}/../config/.bak/infra-${ENV}.json.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backing up existing infrastructure tracking file to: $backup_infra_file"
    cp "$infra_file" "$backup_infra_file"
fi

# Initialize the output files
log_info "Initializing generated infrastructure file: $output_file"
echo '{}' | jq '.common = {} | .tenants = {}' > "$output_file"
log_info "Initializing infrastructure tracking file: $infra_file"
echo '{}' | jq '.project = $project | .environment = $env | .resources = {}' \
  --arg project "$project" --arg env "$ENV" > "$infra_file"

# Derive all resource names from project and environment
rgName="${project}-${ENV}-${region}-rg"
vnetName="${project}-${ENV}-${region}-vnet"
agwName="${project}-${ENV}-${region}-agw"
pipName="${project}-${ENV}-${region}-pip"
kvName="${project}${ENV}${region}kv" # Key Vault names have restrictions
acrName="${project}${ENV}${region}acr" # ACR names have restrictions
lawName="${project}-${ENV}-${region}-law"
agwUamiName="agw-managed-identity" # Managed identity for the AGW

# Print all inferred variables before deployment
log_info "======================================================"
log_info "Inferred Resource Names:"
log_info "======================================================"
log_info "Project:              $project"
log_info "Environment:          $ENV"
log_info "Region:               $region"
log_info "Resource Group:       $rgName"
log_info "VNet:                 $vnetName"
log_info "VNet Address Prefix:  $vnetAddressPrefix"
log_info "App Gateway:          $agwName"
log_info "Public IP:            $pipName"
log_info "Key Vault:            $kvName"
log_info "Container Registry:   $acrName"
log_info "Log Analytics:        $lawName"
log_info "AGW Managed Identity: $agwUamiName"
log_info "======================================================"

# Login to Azure
azure_login

# 1. Create Resource Group
log_info "Checking if resource group exists: $rgName"
if ! az group show --name "$rgName" &>/dev/null; then
    log_info "Creating resource group: $rgName"
    rgId=$(az group create --name "$rgName" --location "$region" --query "id" -o tsv)
    log_success "Created resource group: $rgName"
else
    log_info "Resource group already exists: $rgName"
    rgId=$(az group show --name "$rgName" --query "id" -o tsv || true)
fi
jq --arg rgName "$rgName" --arg rgId "$rgId" \
   '.common += {resourceGroupName: $rgName, resourceGroupId: $rgId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg rgName "$rgName" --arg rgId "$rgId" \
   '.resources += {resourceGroup: {name: $rgName, id: $rgId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

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
    log_success "Created VNet: $vnetName"
else
    log_info "VNet already exists: $vnetName"
    vnetId=$(az network vnet show --name "$vnetName" --resource-group "$rgName" --query "id" -o tsv || true)
fi
jq --arg vnetName "$vnetName" --arg vnetId "$vnetId" \
   '.common += {vnetName: $vnetName, vnetId: $vnetId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg vnetName "$vnetName" --arg vnetId "$vnetId" \
   '.resources += {vnet: {name: $vnetName, id: $vnetId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

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
    log_success "Created Log Analytics Workspace: $lawName"
else
    log_info "Log Analytics Workspace already exists: $lawName"
    lawOutput=$(az monitor log-analytics workspace show --resource-group "$rgName" --workspace-name "$lawName" || true)
    lawId=$(echo "$lawOutput" | jq -r '.id')
    lawCustomerId=$(echo "$lawOutput" | jq -r '.customerId')
fi
jq --arg lawName "$lawName" --arg lawId "$lawId" --arg lawCustomerId "$lawCustomerId" \
   '.common += {logAnalyticsWorkspaceName: $lawName, logAnalyticsWorkspaceId: $lawId, logAnalyticsCustomerId: $lawCustomerId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg lawName "$lawName" --arg lawId "$lawId" \
   '.resources += {logAnalytics: {name: $lawName, id: $lawId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

log_info "Checking if Azure Container Registry exists: $acrName"
if ! az acr show --name "$acrName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Azure Container Registry: $acrName"
    acrId=$(az acr create \
      --resource-group "$rgName" \
      --name "$acrName" \
      --sku "Standard" \
      --admin-enabled false \
      --query "id" -o tsv)
    log_success "Created Azure Container Registry: $acrName"
else
    log_info "Container Registry already exists: $acrName"
    acrId=$(az acr show --name "$acrName" --resource-group "$rgName" --query "id" -o tsv || true)
fi
jq --arg acrName "$acrName" --arg acrId "$acrId" \
   '.common += {acrName: $acrName, acrId: $acrId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg acrName "$acrName" --arg acrId "$acrId" \
   '.resources += {containerRegistry: {name: $acrName, id: $acrId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

log_info "Checking if Key Vault exists: $kvName"
if ! az keyvault show --name "$kvName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Key Vault: $kvName"
    kvId=$(az keyvault create \
      --name "$kvName" \
      --resource-group "$rgName" \
      --location "$region" \
      --enable-rbac-authorization true \
      --query "id" -o tsv)
    log_success "Created Key Vault: $kvName"
else
    log_info "Key Vault already exists: $kvName"
    kvId=$(az keyvault show --name "$kvName" --resource-group "$rgName" --query "id" -o tsv || true)
fi
jq --arg kvName "$kvName" --arg kvId "$kvId" \
   '.common += {keyVaultName: $kvName, keyVaultId: $kvId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg kvName "$kvName" --arg kvId "$kvId" \
   '.resources += {keyVault: {name: $kvName, id: $kvId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

# Assign RBAC roles to current user/SPN for Key Vault operations
log_info "Assigning Key Vault RBAC roles to current user/service principal"
currentUserId=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
if [ -z "$currentUserId" ]; then
    # If not a user, get the service principal object ID
    currentUserId=$(az account show --query user.name -o tsv | xargs -I {} az ad sp show --id {} --query id -o tsv 2>/dev/null || true)
fi

if [ -n "$currentUserId" ]; then
    log_info "Assigning 'Key Vault Certificates Officer' role to current principal"
    # Check if role assignment already exists
    existingAssignment=$(az role assignment list \
        --assignee "$currentUserId" \
        --role "Key Vault Certificates Officer" \
        --scope "$kvId" \
        --query "[0].id" -o tsv 2>/dev/null || true)
    
    if [ -z "$existingAssignment" ]; then
        az role assignment create \
            --assignee "$currentUserId" \
            --role "Key Vault Certificates Officer" \
            --scope "$kvId"
        log_success "Assigned 'Key Vault Certificates Officer' role"
        log_info "Waiting 30 seconds for RBAC propagation..."
        sleep 30
    else
        log_info "Current principal already has 'Key Vault Certificates Officer' role"
    fi
    
    # Also assign Key Vault Secrets Officer for managing secrets
    log_info "Assigning 'Key Vault Secrets Officer' role to current principal"
    existingSecretAssignment=$(az role assignment list \
        --assignee "$currentUserId" \
        --role "Key Vault Secrets Officer" \
        --scope "$kvId" \
        --query "[0].id" -o tsv 2>/dev/null || true)
    
    if [ -z "$existingSecretAssignment" ]; then
        az role assignment create \
            --assignee "$currentUserId" \
            --role "Key Vault Secrets Officer" \
            --scope "$kvId"
        log_success "Assigned 'Key Vault Secrets Officer' role"
    else
        log_info "Current principal already has 'Key Vault Secrets Officer' role"
    fi
else
    log_error "Could not determine current user/service principal ID"
    exit 1
fi

# 4. Upload Certificate to Key Vault
certName=$(jq -r '.customDomain.certificateName' "$CONFIG_FILE" | tr -d ' ') # remove whitespace
log_info "Checking if SSL certificate exists in Key Vault: $certName"
if ! az keyvault certificate show --vault-name "$kvName" --name "$certName" &>/dev/null; then
    log_info "Importing SSL certificate to Key Vault"
    certPassword=$(jq -r '.certificatePassword' "${SCRIPT_DIR}/../creds/astrapiaio.json")
    certFilePathRelative=$(jq -r '.customDomain.certificateFilePath' "$CONFIG_FILE")
    # Resolve certificate path relative to config directory
    certFilePath="${SCRIPT_DIR}/../config/${certFilePathRelative}"
    
    certId=$(az keyvault certificate import \
      --vault-name "$kvName" \
      --name "$certName" \
      --file "$certFilePath" \
      --password "$certPassword" \
      --query "id" -o tsv)
else
    log_info "SSL certificate already exists in Key Vault: $certName"
    certId=$(az keyvault certificate show --vault-name "$kvName" --name "$certName" --query "id" -o tsv || true)
fi

# Get the secret ID for Application Gateway (App Gateway needs the secret, not the certificate)
log_info "Retrieving secret ID for Application Gateway"
certSecretId=$(az keyvault certificate show --vault-name "$kvName" --name "$certName" --query "sid" -o tsv || true)

jq --arg certName "$certName" --arg certId "$certId" --arg certSecretId "$certSecretId" \
   '.common += {certificateName: $certName, certificateId: $certId, certificateSecretId: $certSecretId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg certName "$certName" --arg certId "$certId" --arg certSecretId "$certSecretId" \
   '.resources += {certificate: {name: $certName, id: $certId, secretId: $certSecretId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

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
    log_success "Created Public IP: $pipName"
else
    log_info "Public IP already exists: $pipName"
    pipId=$(az network public-ip show --name "$pipName" --resource-group "$rgName" --query "id" -o tsv || true)|| true)
fi
pipAddress=$(az network public-ip show --ids "$pipId" --query "ipAddress" -o tsv || true)
jq --arg pipName "$pipName" --arg pipId "$pipId" --arg pipAddress "$pipAddress" \
   '.common += {publicIpName: $pipName, publicIpId: $pipId, publicIpAddress: $pipAddress}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg pipName "$pipName" --arg pipId "$pipId" --arg pipAddress "$pipAddress" \
   '.resources += {publicIp: {name: $pipName, id: $pipId, address: $pipAddress}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

log_info "Checking if Managed Identity exists: $agwUamiName"
if ! az identity show --name "$agwUamiName" --resource-group "$rgName" &>/dev/null; then
    log_info "Creating Managed Identity for Application Gateway: $agwUamiName"
    agwUamiId=$(az identity create --name "$agwUamiName" --resource-group "$rgName" --query "id" -o tsv)
else
    log_info "Managed Identity already exists: $agwUamiName"
    agwUamiId=$(az identity show --name "$agwUamiName" --resource-group "$rgName" --query "id" -o tsv || true)|| true)
fi
agwUamiPrincipalId=$(az identity show --name "$agwUamiName" --resource-group "$rgName" --query "principalId" -o tsv || true)
jq --arg uamiName "$agwUamiName" --arg uamiId "$agwUamiId" \
   '.common += {agwManagedIdentityName: $uamiName, agwManagedIdentityId: $uamiId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg uamiName "$agwUamiName" --arg uamiId "$agwUamiId" --arg uamiPrincipalId "$agwUamiPrincipalId" \
   '.resources += {agwManagedIdentity: {name: $uamiName, id: $uamiId, principalId: $uamiPrincipalId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

# Assign RBAC role to Application Gateway Managed Identity for Key Vault access
log_info "Assigning Key Vault RBAC roles to Application Gateway Managed Identity"
# Check if Secrets User role assignment already exists
existingSecretsRole=$(az role assignment list \
    --assignee "$agwUamiPrincipalId" \
    --role "Key Vault Secrets User" \
    --scope "$kvId" \
    --query "[0].id" -o tsv 2>/dev/null || true)

if [ -z "$existingSecretsRole" ]; then
    log_info "Assigning 'Key Vault Secrets User' role to App Gateway Managed Identity"
    az role assignment create \
        --assignee "$agwUamiPrincipalId" \
        --role "Key Vault Secrets User" \
        --scope "$kvId"
    log_success "Assigned 'Key Vault Secrets User' role"
else
    log_info "App Gateway Managed Identity already has 'Key Vault Secrets User' role"
fi

# Check if Certificate User role assignment already exists
existingCertRole=$(az role assignment list \
    --assignee "$agwUamiPrincipalId" \
    --role "Key Vault Certificate User" \
    --scope "$kvId" \
    --query "[0].id" -o tsv 2>/dev/null || true)

if [ -z "$existingCertRole" ]; then
    log_info "Assigning 'Key Vault Certificate User' role to App Gateway Managed Identity"
    az role assignment create \
        --assignee "$agwUamiPrincipalId" \
        --role "Key Vault Certificate User" \
        --scope "$kvId"
    log_success "Assigned 'Key Vault Certificate User' role"
else
    log_info "App Gateway Managed Identity already has 'Key Vault Certificate User' role"
fi

log_info "Checking if Application Gateway exists: $agwName"
if ! az network application-gateway show --name "$agwName" --resource-group "$rgName" &>/dev/null; then
    log_info "Deploying Application Gateway: $agwName (this may take several minutes)"
    agwId=$(az network application-gateway create \
      --name "$agwName" \
      --resource-group "$rgName" \
      --location "$region" \
      --sku "Standard_v2" \
      --capacity 2 \
      --public-ip-address "$pipName" \
      --vnet-name "$vnetName" \
      --subnet "snet-appgateway" \
      --identity "$agwUamiId" \
      --priority 100 \
      --query "id" -o tsv)
    log_success "Created Application Gateway: $agwName"
else
    log_info "Application Gateway already exists: $agwName"
    agwId=$(az network application-gateway show --name "$agwName" --resource-group "$rgName" --query "id" -o tsv || true)
fi
jq --arg agwName "$agwName" --arg agwId "$agwId" \
   '.common += {appGatewayName: $agwName, appGatewayId: $agwId}' \
   "$output_file" > tmp.$$.json && mv tmp.$$.json "$output_file"
# Update infra tracking file
jq --arg agwName "$agwName" --arg agwId "$agwId" \
   '.resources += {appGateway: {name: $agwName, id: $agwId}}' \
   "$infra_file" > tmp.$$.json && mv tmp.$$.json "$infra_file"

# 6. Configure Application Gateway with SSL Certificate
log_info "Adding SSL certificate from Key Vault to Application Gateway"
certSecretId=$(jq -r '.common.sslCertificateSecretId' "$output_file")
certName=$(jq -r '.common.sslCertificateName' "$output_file")

log_info "Checking if SSL certificate '$certName' is already added to Application Gateway"
if ! az network application-gateway ssl-cert show --gateway-name "$agwName" --resource-group "$rgName" --name "$certName" &>/dev/null; then
    log_info "Adding SSL certificate '$certName' to Application Gateway (using secret ID)"
    az network application-gateway ssl-cert create \
        --gateway-name "$agwName" \
        --resource-group "$rgName" \
        --name "$certName" \
        --key-vault-secret-id "$certSecretId"
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
