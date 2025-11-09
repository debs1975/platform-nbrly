#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
CERT_FILE=${2}
CERT_PASSWORD=${3}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/parameters-${ENVIRONMENT}.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Infrastructure config not found: $CONFIG_FILE"
    echo "Usage: ./upload-ssl-certificate.sh [dev|staging|prod] <certificate-file> [password]"
    exit 1
fi

if [ -z "$CERT_FILE" ]; then
    echo "Certificate file not provided"
    echo ""
    echo "Usage: ./upload-ssl-certificate.sh [environment] <certificate-file> [password]"
    echo ""
    echo "Examples:"
    echo "  # Upload PFX with password"
    echo "  ./upload-ssl-certificate.sh dev /path/to/cert.pfx 'MyPassword123'"
    echo ""
    echo "  # Upload PEM (no password)"
    echo "  ./upload-ssl-certificate.sh dev /path/to/cert.pem"
    echo ""
    echo "  # Upload staging certificate"
    echo "  ./upload-ssl-certificate.sh staging /path/to/cert.pfx 'MyPassword123'"
    echo ""
    exit 1
fi

if [ ! -f "$CERT_FILE" ]; then
    echo "Certificate file not found: $CERT_FILE"
    exit 1
fi

PROJECT_NAME=$(jq -r '.projectName' "$CONFIG_FILE")
ENV=$(jq -r '.environment' "$CONFIG_FILE")
REGION=$(jq -r '.location' "$CONFIG_FILE")
KV_CERT_NAME=$(jq -r '.customDomain.keyVaultCertificateName' "$CONFIG_FILE")

RG_NAME="${PROJECT_NAME}-${ENV}-${REGION}-rg"
KEY_VAULT_NAME="${PROJECT_NAME}-${ENV}-${REGION}-kv"

source "${SCRIPT_DIR}/helpers/azure-login.sh"
azure_login "$ENV"

echo "=========================================="
echo "Upload SSL Certificate to Key Vault"
echo "=========================================="
echo "Environment: ${ENV}"
echo "Key Vault: ${KEY_VAULT_NAME}"
echo "Certificate Name: ${KV_CERT_NAME}"
echo "Certificate File: ${CERT_FILE}"
echo "Resource Group: ${RG_NAME}"
echo "=========================================="

echo ""
echo "Verifying Key Vault exists..."
if ! az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RG_NAME" &>/dev/null; then
    echo "Key Vault not found: $KEY_VAULT_NAME"
    echo "Deploy security infrastructure first: ./scripts/02-deploy-security.sh ${ENV}"
    exit 1
fi

echo "Key Vault verified: $KEY_VAULT_NAME"

# Detect certificate format
CERT_EXT="${CERT_FILE##*.}"
CERT_FORMAT="unknown"

case "${CERT_EXT,,}" in
    pfx|p12)
        CERT_FORMAT="pfx"
        ;;
    pem|crt|cer)
        CERT_FORMAT="pem"
        ;;
    *)
        echo "Unknown certificate format: .$CERT_EXT"
        echo "Supported formats: .pfx, .p12, .pem, .crt, .cer"
        exit 1
        ;;
esac

echo "Detected certificate format: $CERT_FORMAT"

# Check if certificate already exists
echo ""
echo "Checking if certificate already exists in Key Vault..."
EXISTING_CERT=$(az keyvault certificate show \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$KV_CERT_NAME" \
    --query id -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_CERT" ]; then
    echo "WARNING: Certificate '${KV_CERT_NAME}' already exists in Key Vault"
    
    # Show existing certificate details
    echo ""
    echo "Existing certificate details:"
    az keyvault certificate show \
        --vault-name "$KEY_VAULT_NAME" \
        --name "$KV_CERT_NAME" \
        --query "{name:name,enabled:attributes.enabled,created:attributes.created,expires:attributes.expires,issuer:issuer.name}" \
        --output table
    
    echo ""
    read -p "Do you want to replace it? (yes/no): " REPLACE_CERT
    
    if [ "$REPLACE_CERT" != "yes" ]; then
        echo "Upload cancelled. Existing certificate unchanged."
        exit 0
    fi
    
    echo "Deleting existing certificate..."
    az keyvault certificate delete \
        --vault-name "$KEY_VAULT_NAME" \
        --name "$KV_CERT_NAME" \
        --output none
    
    echo "Waiting for certificate deletion to complete..."
    sleep 5
fi

# Import certificate based on format
echo ""
echo "Uploading certificate to Key Vault..."

if [ "$CERT_FORMAT" == "pfx" ]; then
    # PFX format - requires password
    if [ -z "$CERT_PASSWORD" ]; then
        echo ""
        read -s -p "Enter certificate password: " CERT_PASSWORD
        echo ""
        
        if [ -z "$CERT_PASSWORD" ]; then
            echo "Password is required for PFX certificates"
            exit 1
        fi
    fi
    
    az keyvault certificate import \
        --vault-name "$KEY_VAULT_NAME" \
        --name "$KV_CERT_NAME" \
        --file "$CERT_FILE" \
        --password "$CERT_PASSWORD" \
        --output none
    
elif [ "$CERT_FORMAT" == "pem" ]; then
    # PEM format - may or may not need password
    if [ -n "$CERT_PASSWORD" ]; then
        az keyvault certificate import \
            --vault-name "$KEY_VAULT_NAME" \
            --name "$KV_CERT_NAME" \
            --file "$CERT_FILE" \
            --password "$CERT_PASSWORD" \
            --output none
    else
        az keyvault certificate import \
            --vault-name "$KEY_VAULT_NAME" \
            --name "$KV_CERT_NAME" \
            --file "$CERT_FILE" \
            --output none
    fi
fi

echo "Certificate uploaded successfully!"

# Verify upload and display details
echo ""
echo "Verifying certificate upload..."

CERT_DETAILS=$(az keyvault certificate show \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$KV_CERT_NAME" \
    --query "{name:name,enabled:attributes.enabled,created:attributes.created,expires:attributes.expires,thumbprint:x509Thumbprint,issuer:issuer.name}" \
    --output json)

echo ""
echo "Certificate Details:"
echo "=========================================="
echo "$CERT_DETAILS" | jq -r '
    "Name:         \(.name)",
    "Enabled:      \(.enabled)",
    "Created:      \(.created)",
    "Expires:      \(.expires)",
    "Thumbprint:   \(.thumbprint)",
    "Issuer:       \(.issuer)"
'
echo "=========================================="

# Get certificate ID for reference
CERT_ID=$(az keyvault certificate show \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$KV_CERT_NAME" \
    --query id -o tsv)

echo ""
echo "Certificate ID: $CERT_ID"

# Check expiration
EXPIRES=$(echo "$CERT_DETAILS" | jq -r '.expires')
EXPIRES_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${EXPIRES%+*}" +%s 2>/dev/null || echo "0")
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRES_EPOCH - $CURRENT_EPOCH) / 86400 ))

if [ "$DAYS_UNTIL_EXPIRY" -lt 0 ]; then
    echo ""
    echo "WARNING: Certificate has EXPIRED!"
elif [ "$DAYS_UNTIL_EXPIRY" -lt 30 ]; then
    echo ""
    echo "WARNING: Certificate expires in ${DAYS_UNTIL_EXPIRY} days"
elif [ "$DAYS_UNTIL_EXPIRY" -lt 90 ]; then
    echo ""
    echo "Notice: Certificate expires in ${DAYS_UNTIL_EXPIRY} days"
else
    echo ""
    echo "Certificate is valid for ${DAYS_UNTIL_EXPIRY} days"
fi

echo ""
echo "=========================================="
echo "SSL Certificate Upload Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Configure DNS records (CNAME and TXT)"
echo "  2. Deploy SSL configuration:"
echo "     ./scripts/06-deploy-ssl.sh ${ENV}"
echo ""
echo "View certificate:"
echo "  az keyvault certificate show \\"
echo "    --vault-name ${KEY_VAULT_NAME} \\"
echo "    --name ${KV_CERT_NAME}"
echo ""
echo "Download certificate (public key only):"
echo "  az keyvault certificate download \\"
echo "    --vault-name ${KEY_VAULT_NAME} \\"
echo "    --name ${KV_CERT_NAME} \\"
echo "    --file ${KV_CERT_NAME}.cer"
echo "=========================================="
