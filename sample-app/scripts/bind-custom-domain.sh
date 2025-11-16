#!/bin/bash
set -euo pipefail

# ============================================================================
# Script: bind-custom-domain.sh
# Purpose: Bind custom domain and SSL certificate to Container App
# Usage: ./bind-custom-domain.sh [environment] <app-name>
# ============================================================================
# This script:
# - Adds custom hostname to Container App
# - Binds SSL certificate from Container Apps Environment
# - Provides DNS configuration instructions
# - Reads custom domain from customDomain.domainName in infra-config-{env}.json
# ============================================================================

ENVIRONMENT=${1:-dev}
APP_NAME_PARAM=${2:-}

if [ -z "$APP_NAME_PARAM" ]; then
    echo "ERROR: Application name is required"
    echo ""
    echo "Usage: $0 [environment] <app-name>"
    echo ""
    echo "Arguments:"
    echo "  environment    : Optional - Environment (dev, staging, prod) [default: dev]"
    echo "  app-name       : REQUIRED - Application name (app1, app2, etc.)"
    echo ""
    echo "Examples:"
    echo "  $0 dev app1          # Bind custom domain to app1 in dev"
    echo "  $0 dev app2          # Bind custom domain to app2 in dev"
    echo "  $0 prod app1         # Bind custom domain to app1 in prod"
    echo ""
    echo "Note:"
    echo "  - Custom domain is read from customDomain.domainName in infra-config-{env}.json"
    echo "  - Ensure customDomain.enabled is true in the config file"
    echo ""
    echo "Prerequisites:"
    echo "  - Certificate must be uploaded to Container Apps Environment"
    echo "  - Run: ../../iac-cli/scripts/06-deploy-ssl.sh <environment>"
    exit 1
fi

# Validate app name
if [[ ! "$APP_NAME_PARAM" =~ ^app[0-9]+$ ]]; then
    echo "ERROR: Invalid app name: $APP_NAME_PARAM"
    echo "Valid format: app1, app2, app3, etc."
    exit 1
fi

# ============================================================================
# Load Configuration
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_CONFIG_FILE="${SCRIPT_DIR}/../config/infra-config-${ENVIRONMENT}.json"
APP_CONFIG_FILE="${SCRIPT_DIR}/../config/${APP_NAME_PARAM}-config-${ENVIRONMENT}.json"

if [ ! -f "$INFRA_CONFIG_FILE" ]; then
    echo "❌ Infrastructure config not found: $INFRA_CONFIG_FILE"
    exit 1
fi

if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo "❌ Application config not found: $APP_CONFIG_FILE"
    exit 1
fi

# Extract infrastructure configuration
PROJECT_NAME=$(jq -r '.projectName' "$INFRA_CONFIG_FILE")
ENV=$(jq -r '.environment' "$INFRA_CONFIG_FILE")
REGION=$(jq -r '.location' "$INFRA_CONFIG_FILE")
RG_NAME=$(jq -r '.resourceGroup.name' "$INFRA_CONFIG_FILE")
ENV_NAME=$(jq -r '.containerAppsEnvironment.name' "$INFRA_CONFIG_FILE")
CERT_NAME=$(jq -r '.customDomain.certificateName // empty' "$INFRA_CONFIG_FILE")

# Get custom domain from infra config (required)
CUSTOM_DOMAIN=$(jq -r '.customDomain.domainName // empty' "$INFRA_CONFIG_FILE")

if [ -z "$CUSTOM_DOMAIN" ]; then
    echo "❌ Custom domain not found in infra config"
    echo "   Add customDomain.domainName to $INFRA_CONFIG_FILE"
    echo ""
    echo "   Example config:"
    echo "   {"
    echo "     \"customDomain\": {"
    echo "       \"enabled\": true,"
    echo "       \"domainName\": \"app.example.com\","
    echo "       \"certificateName\": \"example-cert\""
    echo "     }"
    echo "   }"
    exit 1
fi

echo "ℹ️  Using custom domain from infra config: $CUSTOM_DOMAIN"

# Get app name from app config
APP_NAME_SUFFIX=$(jq -r '.application.name // empty' "$APP_CONFIG_FILE")
if [ -z "$APP_NAME_SUFFIX" ]; then
    echo "❌ Application name not found in app config: application.name"
    exit 1
fi

# Construct container app name
APP_NAME="${PROJECT_NAME}-${ENV}-${REGION}-${APP_NAME_SUFFIX}-ca"

echo ""
echo "=========================================="
echo "🌐 Custom Domain Binding"
echo "=========================================="
echo "Environment: $ENV"
echo "App Parameter: $APP_NAME_PARAM"
echo "Container App: $APP_NAME"
echo "Custom Domain: $CUSTOM_DOMAIN"
echo "Certificate: ${CERT_NAME:-<Azure-managed>}"
echo ""

# ============================================================================
# Azure Authentication
# ============================================================================
# Use inline authentication instead of sourcing external script
echo "Authenticating with Azure..."

# Check if already logged in
if ! az account show &>/dev/null; then
    echo "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Set subscription from infra config
SUBSCRIPTION_ID=$(jq -r '.subscriptionId // empty' "$INFRA_CONFIG_FILE")
if [ -n "$SUBSCRIPTION_ID" ]; then
    echo "Setting subscription: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Verify subscription
CURRENT_SUB=$(az account show --query id -o tsv)
echo "Using subscription: $CURRENT_SUB"
echo ""

# ============================================================================
# Validate Prerequisites
# ============================================================================
echo "Validating prerequisites..."

# Check Container App exists
if ! az containerapp show --name "$APP_NAME" --resource-group "$RG_NAME" --output none 2>/dev/null; then
    echo "❌ Container App not found: $APP_NAME"
    echo "   Deploy the app first: ./deploy-app.sh $APP_NAME_PARAM $ENV"
    exit 1
fi

# Check certificate exists in environment
if [ -n "$CERT_NAME" ]; then
    CERT_EXISTS=$(az containerapp env certificate list \
        --name "$ENV_NAME" \
        --resource-group "$RG_NAME" \
        --query "[?name=='$CERT_NAME'].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -z "$CERT_EXISTS" ]; then
        echo "❌ Certificate not found in environment: $CERT_NAME"
        echo "   Upload certificate first: ../../iac-cli/scripts/06-deploy-ssl.sh $ENV"
        echo "   Or run: cd ../../iac-cli && ./scripts/06-deploy-ssl.sh $ENV"
        exit 1
    fi
    
    echo "✅ Certificate found: $CERT_NAME"
else
    echo "⚠️  No certificate configured, will use Azure-managed certificate"
fi

echo ""

# ============================================================================
# Get DNS Configuration Requirements
# ============================================================================
echo "Retrieving DNS configuration requirements..."

# Get the static IP address of the Container Apps Environment
STATIC_IP=$(az containerapp env show \
    --name "$ENV_NAME" \
    --resource-group "$RG_NAME" \
    --query properties.staticIp \
    --output tsv)

VERIFICATION_ID=$(az containerapp show \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --query properties.customDomainVerificationId \
    --output tsv)

# Extract subdomain and root domain for DNS zone operations
SUBDOMAIN=$(echo "$CUSTOM_DOMAIN" | sed 's/\.[^.]*\.[^.]*$//')
ROOT_DOMAIN=$(echo "$CUSTOM_DOMAIN" | sed 's/^[^.]*\.//')

# Try to detect DNS zone resource group (optional, non-blocking)
echo ""
echo "Checking for Azure DNS zone..."
DNS_ZONE_RG=$(az network dns zone list \
    --query "[?name=='$ROOT_DOMAIN'].resourceGroup | [0]" \
    --output tsv 2>/dev/null || echo "")

if [ -n "$DNS_ZONE_RG" ]; then
    echo "✅ Found DNS zone '$ROOT_DOMAIN' in resource group: $DNS_ZONE_RG"
    DNS_ZONE_FOUND=true
else
    echo "ℹ️  DNS zone not found in current subscription (external DNS provider or different subscription)"
    DNS_ZONE_FOUND=false
fi

echo ""
echo "=========================================="
echo "📋 DNS Configuration Required"
echo "=========================================="
echo ""
echo "Add these DNS records to your Azure DNS Zone: $ROOT_DOMAIN"
echo ""
echo "─────────────────────────────────────────"
echo "1. A Record (for traffic routing)"
echo "─────────────────────────────────────────"
echo "   Type:  A"
echo "   Name:  $SUBDOMAIN"
echo "   Value: $STATIC_IP"
echo "   TTL:   3600"
echo ""
echo "─────────────────────────────────────────"
echo "2. TXT Record (for domain verification)"
echo "─────────────────────────────────────────"
echo "   Type:  TXT"
echo "   Name:  asuid.$SUBDOMAIN"
echo "   Value: $VERIFICATION_ID"
echo "   TTL:   3600"
echo ""
echo "=========================================="
echo "📝 Manual DNS Zone Update Instructions"
echo "=========================================="
echo ""
echo "Option 1: Azure Portal"
echo "  1. Go to Azure Portal → DNS zones"
echo "  2. Select zone: $ROOT_DOMAIN"
echo "  3. Click '+ Record set'"
echo "  4. Add the records above"
echo ""
echo "Option 2: Azure CLI Commands"
echo ""
if [ "$DNS_ZONE_FOUND" = true ]; then
    echo "  ✅ Copy-paste ready commands for your DNS zone:"
    echo ""
    echo "  # Add A record"
    echo "  az network dns record-set a add-record \\"
    echo "    --resource-group $DNS_ZONE_RG \\"
    echo "    --zone-name $ROOT_DOMAIN \\"
    echo "    --record-set-name $SUBDOMAIN \\"
    echo "    --ipv4-address $STATIC_IP"
    echo ""
    echo "  # Add TXT record for verification"
    echo "  az network dns record-set txt add-record \\"
    echo "    --resource-group $DNS_ZONE_RG \\"
    echo "    --zone-name $ROOT_DOMAIN \\"
    echo "    --record-set-name asuid.$SUBDOMAIN \\"
    echo "    --value \"$VERIFICATION_ID\""
else
    echo "  Note: Replace <dns-zone-resource-group> with your DNS zone's resource group"
    echo ""
    echo "  # Add A record"
    echo "  az network dns record-set a add-record \\"
    echo "    --resource-group <dns-zone-resource-group> \\"
    echo "    --zone-name $ROOT_DOMAIN \\"
    echo "    --record-set-name $SUBDOMAIN \\"
    echo "    --ipv4-address $STATIC_IP"
    echo ""
    echo "  # Add TXT record for verification"
    echo "  az network dns record-set txt add-record \\"
    echo "    --resource-group <dns-zone-resource-group> \\"
    echo "    --zone-name $ROOT_DOMAIN \\"
    echo "    --record-set-name asuid.$SUBDOMAIN \\"
    echo "    --value \"$VERIFICATION_ID\""
fi
echo ""
echo "=========================================="
echo ""
echo "⚠️  IMPORTANT: This script does NOT automatically create DNS records."
echo "   You must manually add the records above to your DNS zone."
echo ""

read -p "Have you configured these DNS records? (yes/no): " DNS_CONFIRMED
if [ "$DNS_CONFIRMED" != "yes" ]; then
    echo ""
    echo "Please configure DNS records and re-run this script."
    exit 0
fi

# ============================================================================
# Verify DNS Propagation
# ============================================================================
echo ""
echo "Verifying DNS propagation..."
sleep 3

A_RECORD_RESULT=$(dig +short "$CUSTOM_DOMAIN" A 2>/dev/null | head -1 || echo "")
if [ -z "$A_RECORD_RESULT" ]; then
    echo "⚠️  A record not found or not propagated yet"
    echo "   DNS propagation can take 5-30 minutes"
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Exiting. Please wait for DNS propagation and try again."
        exit 0
    fi
else
    echo "✅ A record found: $A_RECORD_RESULT"
    if [ "$A_RECORD_RESULT" != "$STATIC_IP" ]; then
        echo "⚠️  Warning: A record ($A_RECORD_RESULT) doesn't match expected static IP ($STATIC_IP)"
        read -p "Continue anyway? (yes/no): " CONTINUE
        if [ "$CONTINUE" != "yes" ]; then
            echo "Exiting. Please update DNS records and try again."
            exit 0
        fi
    fi
fi

# ============================================================================
# Add Custom Hostname
# ============================================================================
echo ""
echo "Adding custom hostname to Container App..."

# Check if hostname already exists
EXISTING_HOSTNAME=$(az containerapp hostname list \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --query "[?name=='$CUSTOM_DOMAIN'].name" \
    --output tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_HOSTNAME" ]; then
    echo "ℹ️  Hostname already added: $CUSTOM_DOMAIN"
else
    az containerapp hostname add \
        --resource-group "$RG_NAME" \
        --name "$APP_NAME" \
        --hostname "$CUSTOM_DOMAIN" \
        --output none
    
    echo "✅ Hostname added: $CUSTOM_DOMAIN"
fi

# ============================================================================
# Bind SSL Certificate
# ============================================================================
echo ""
if [ -n "$CERT_NAME" ]; then
    echo "Binding SSL certificate to hostname..."
    
    # Get certificate thumbprint
    CERT_THUMBPRINT=$(az containerapp env certificate list \
        --name "$ENV_NAME" \
        --resource-group "$RG_NAME" \
        --query "[?name=='$CERT_NAME'].properties.thumbprint" \
        --output tsv)
    
    if [ -z "$CERT_THUMBPRINT" ]; then
        echo "❌ Failed to retrieve certificate thumbprint"
        exit 1
    fi
    
    echo "Certificate thumbprint: ${CERT_THUMBPRINT:0:16}..."
    
    # Bind certificate to hostname
    az containerapp hostname bind \
        --resource-group "$RG_NAME" \
        --name "$APP_NAME" \
        --hostname "$CUSTOM_DOMAIN" \
        --environment "$ENV_NAME" \
        --thumbprint "$CERT_THUMBPRINT" \
        --output none
    
    echo "✅ SSL certificate bound successfully"
else
    echo "Enabling Azure-managed certificate..."
    
    # Use Azure-managed certificate (free, auto-renewing)
    # With A records, use HTTP validation instead of CNAME
    az containerapp hostname bind \
        --resource-group "$RG_NAME" \
        --name "$APP_NAME" \
        --hostname "$CUSTOM_DOMAIN" \
        --environment "$ENV_NAME" \
        --validation-method HTTP \
        --output none
    
    echo "✅ Azure-managed certificate enabled"
    echo "⏳ Certificate provisioning may take 5-10 minutes"
fi

# ============================================================================
# Verify Configuration
# ============================================================================
echo ""
echo "Verifying configuration..."
sleep 2

BOUND_HOSTNAMES=$(az containerapp hostname list \
    --resource-group "$RG_NAME" \
    --name "$APP_NAME" \
    --output table 2>/dev/null)

echo ""
echo "Current hostnames for $APP_NAME:"
echo "$BOUND_HOSTNAMES"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=========================================="
echo "✅ Custom Domain Binding Complete!"
echo "=========================================="
echo "Container App: $APP_NAME"
echo "Custom Domain: $CUSTOM_DOMAIN"
echo "Default Domain: $APP_FQDN"
echo ""
echo "Your application is now accessible at:"
echo "  https://$CUSTOM_DOMAIN"
echo ""
echo "Verification:"
echo "  curl -I https://$CUSTOM_DOMAIN"
echo "  curl https://$CUSTOM_DOMAIN/health"
echo ""
echo "SSL Certificate Check:"
echo "  openssl s_client -connect ${CUSTOM_DOMAIN}:443 -servername ${CUSTOM_DOMAIN}"
echo ""
echo "View all hostnames:"
echo "  az containerapp hostname list \\"
echo "    --resource-group $RG_NAME \\"
echo "    --name $APP_NAME \\"
echo "    --output table"
echo "=========================================="
echo ""
