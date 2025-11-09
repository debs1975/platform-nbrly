#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/parameters-${ENVIRONMENT}.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Infrastructure config not found: $CONFIG_FILE"
    echo "Usage: ./06-deploy-ssl.sh [dev|staging|prod]"
    exit 1
fi

PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
REGION=$(jq -r '.location' "$CONFIG_FILE")

CUSTOM_DOMAIN_ENABLED=$(jq -r '.customDomain.enabled' "$CONFIG_FILE")
CUSTOM_DOMAIN=$(jq -r '.customDomain.domainName' "$CONFIG_FILE")
CERT_NAME=$(jq -r '.customDomain.certificateName' "$CONFIG_FILE")
KV_CERT_NAME=$(jq -r '.customDomain.keyVaultCertificateName' "$CONFIG_FILE")

RG_NAME="${PROJECT_NAME}-${ENV}-${REGION}-rg"
ENV_NAME="${PROJECT_NAME}-${ENV}-${REGION}-env"
KEY_VAULT_NAME="${PROJECT_NAME}-${ENV}-${REGION}-kv"

source "${SCRIPT_DIR}/helpers/azure-login.sh"
azure_login "$ENV"

echo "=========================================="
echo "Configuring Custom Domain and SSL/TLS"
echo "=========================================="
echo "Environment: ${ENV}"
echo "Container Apps Env: ${ENV_NAME}"
echo "Custom Domain: ${CUSTOM_DOMAIN}"
echo "Certificate: ${CERT_NAME}"
echo "Resource Group: ${RG_NAME}"
echo "=========================================="

if [ "$CUSTOM_DOMAIN_ENABLED" != "true" ]; then
    echo "Custom domain is not enabled in configuration."
    echo "Set customDomain.enabled to true in ${CONFIG_FILE}"
    exit 0
fi

echo ""
echo "Verifying Container Apps Environment exists..."
if ! az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "Container Apps Environment not found: $ENV_NAME"
    echo "Deploy infrastructure first: ./scripts/03-deploy-compute.sh ${ENV}"
    exit 1
fi

echo "Container Apps Environment verified"

echo ""
echo "Verifying Key Vault and certificate..."
if ! az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "Key Vault not found: $KEY_VAULT_NAME"
    echo "Deploy security infrastructure first: ./scripts/02-deploy-security.sh ${ENV}"
    exit 1
fi

KV_CERT_ID=$(az keyvault certificate show \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$KV_CERT_NAME" \
    --query id -o tsv 2>/dev/null || echo "")

if [ -z "$KV_CERT_ID" ]; then
    echo ""
    echo "Certificate '${KV_CERT_NAME}' not found in Key Vault '${KEY_VAULT_NAME}'"
    echo ""
    echo "To upload a wildcard certificate to Key Vault:"
    echo "  1. Obtain *.astrapia.io certificate (PFX/PEM format)"
    echo "  2. Upload to Key Vault:"
    echo ""
    echo "     az keyvault certificate import \\"
    echo "       --vault-name ${KEY_VAULT_NAME} \\"
    echo "       --name ${KV_CERT_NAME} \\"
    echo "       --file /path/to/certificate.pfx \\"
    echo "       --password '<certificate-password>'"
    echo ""
    echo "  3. Re-run this script"
    echo ""
    exit 1
fi

echo "Certificate verified in Key Vault: $KV_CERT_ID"

echo ""
echo "Checking if certificate already exists in Container Apps Environment..."
EXISTING_CERT=$(az containerapp env certificate list \
    --resource-group "$RG_NAME" \
    --name "$ENV_NAME" \
    --query "[?name=='${CERT_NAME}'].id" -o tsv 2>/dev/null || echo "")

if [ -z "$EXISTING_CERT" ]; then
    echo "Uploading certificate to Container Apps Environment..."
    
    az containerapp env certificate upload \
        --resource-group "$RG_NAME" \
        --name "$ENV_NAME" \
        --certificate-name "$CERT_NAME" \
        --certificate-identity "system" \
        --certificate-key-vault-url "$KV_CERT_ID" \
        --output none
    
    echo "Certificate uploaded: $CERT_NAME"
else
    echo "Certificate already exists in environment: $CERT_NAME"
fi

CERT_ID=$(az containerapp env certificate list \
    --resource-group "$RG_NAME" \
    --name "$ENV_NAME" \
    --query "[?name=='${CERT_NAME}'].id" -o tsv)

echo "Certificate ID: $CERT_ID"

echo ""
echo "Checking DNS configuration..."
echo ""
echo "IMPORTANT: Before binding the custom domain, configure DNS:"
echo "  1. Create a CNAME record in your DNS provider:"
echo "     Name: ${CUSTOM_DOMAIN}"
echo "     Type: CNAME"
echo "     Value: <environment-default-domain>"
echo ""

ENV_DEFAULT_DOMAIN=$(az containerapp env show \
    --name "$ENV_NAME" \
    --resource-group "$RG_NAME" \
    --query properties.defaultDomain -o tsv)

echo "  2. Create a TXT record for domain validation:"
echo "     Name: asuid.${CUSTOM_DOMAIN}"
echo "     Type: TXT"
echo "     Value: <verification-id>"
echo ""

VERIFICATION_ID=$(az containerapp env show \
    --name "$ENV_NAME" \
    --resource-group "$RG_NAME" \
    --query properties.customDomainConfiguration.customDomainVerificationId -o tsv)

echo "DNS Records to create:"
echo "=========================================="
echo "CNAME Record:"
echo "  Name:  ${CUSTOM_DOMAIN}"
echo "  Type:  CNAME"
echo "  Value: ${ENV_DEFAULT_DOMAIN}"
echo ""
echo "TXT Record (for validation):"
echo "  Name:  asuid.${CUSTOM_DOMAIN}"
echo "  Type:  TXT"
echo "  Value: ${VERIFICATION_ID}"
echo "=========================================="
echo ""

read -p "Have you configured the DNS records? (yes/no): " DNS_CONFIRMED

if [ "$DNS_CONFIRMED" != "yes" ]; then
    echo ""
    echo "Please configure DNS records and re-run this script."
    echo "Script saved DNS information above."
    exit 0
fi

echo ""
echo "Verifying DNS propagation..."
sleep 5

CNAME_CHECK=$(dig +short "$CUSTOM_DOMAIN" CNAME | grep -i "azurecontainerapps.io" || echo "")
if [ -z "$CNAME_CHECK" ]; then
    echo "WARNING: CNAME record not found or not propagated yet."
    echo "DNS propagation can take a few minutes to several hours."
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        exit 0
    fi
fi

echo ""
echo "Adding custom domain to Container Apps Environment..."

EXISTING_DOMAIN=$(az containerapp env show \
    --name "$ENV_NAME" \
    --resource-group "$RG_NAME" \
    --query "properties.customDomainConfiguration.dnsSuffix" -o tsv 2>/dev/null || echo "")

if [ "$EXISTING_DOMAIN" == "$CUSTOM_DOMAIN" ]; then
    echo "Custom domain already configured: $CUSTOM_DOMAIN"
else
    az containerapp env update \
        --resource-group "$RG_NAME" \
        --name "$ENV_NAME" \
        --dns-suffix "$CUSTOM_DOMAIN" \
        --certificate-identity "system" \
        --certificate-key-vault-url "$KV_CERT_ID" \
        --output none
    
    echo "Custom domain configured: $CUSTOM_DOMAIN"
fi

echo ""
echo "=========================================="
echo "SSL/TLS Configuration Complete!"
echo "=========================================="
echo "Environment: ${ENV_NAME}"
echo "Custom Domain: ${CUSTOM_DOMAIN}"
echo "Certificate: ${CERT_NAME}"
echo ""
echo "Your Container Apps Environment is now accessible via:"
echo "  https://${CUSTOM_DOMAIN}"
echo ""
echo "All container apps in this environment will be accessible via:"
echo "  https://<app-name>.${CUSTOM_DOMAIN}"
echo ""
echo "With HTTP routing enabled:"
echo "  https://${CUSTOM_DOMAIN}/app1"
echo "  https://${CUSTOM_DOMAIN}/app2"
echo ""
echo "Verify SSL certificate:"
echo "  curl -v https://${CUSTOM_DOMAIN}"
echo "  openssl s_client -connect ${CUSTOM_DOMAIN}:443 -servername ${CUSTOM_DOMAIN}"
echo ""
echo "View certificate details:"
echo "  az containerapp env certificate list \\"
echo "    --resource-group ${RG_NAME} \\"
echo "    --name ${ENV_NAME} \\"
echo "    --output table"
echo "=========================================="
