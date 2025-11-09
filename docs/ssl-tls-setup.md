# Custom Domain and SSL/TLS Configuration

This document explains how to configure custom domains with SSL/TLS certificates for Azure Container Apps Environment.

## Overview

Azure Container Apps Environment supports custom domains with TLS/SSL certificates, allowing you to:
- Use your own domain instead of the default `*.azurecontainerapps.io` domain
- Secure all traffic with your own SSL/TLS certificate
- Support wildcard certificates for all apps in the environment
- Provide a branded experience for your applications

## Architecture

```
Client Request (HTTPS)
    ↓
Custom Domain (nbrly-dev.astrapia.io)
    ↓
TLS Termination (*.astrapia.io certificate)
    ↓
Container Apps Environment Gateway
    ↓
Container Apps (via routing or individual FQDNs)
```

## Prerequisites

### 1. Domain Ownership

You must own or control the domain you want to use:
- **Dev**: `nbrly-dev.astrapia.io`
- **Staging**: `nbrly-staging.astrapia.io`
- **Prod**: `nbrly-prod.astrapia.io`

### 2. SSL/TLS Certificate

You need a wildcard certificate for `*.astrapia.io` that covers all environments.

**Certificate Requirements:**
- Format: PFX or PEM
- Type: Wildcard (`*.astrapia.io`) or specific subdomain
- Valid: Not expired
- Chain: Complete certificate chain included

**Obtaining a Certificate:**

Option A: **Azure App Service Certificate** (Recommended)
```bash
# Purchase and auto-renew certificate via Azure
az appservice domain create \
  --resource-group certificates-rg \
  --hostname astrapia.io

az appservice certificate create \
  --resource-group certificates-rg \
  --name astrapia-wildcard \
  --hostname *.astrapia.io
```

Option B: **Let's Encrypt** (Free)
```bash
# Using certbot
sudo certbot certonly \
  --manual \
  --preferred-challenges dns \
  -d "*.astrapia.io"

# Convert to PFX
openssl pkcs12 -export \
  -out astrapia-wildcard.pfx \
  -inkey privkey.pem \
  -in fullchain.pem
```

Option C: **Commercial CA** (DigiCert, GoDaddy, etc.)
- Purchase wildcard certificate from provider
- Download in PFX or PEM format

### 3. Upload Certificate to Key Vault

Before running the deployment script, upload your certificate to Azure Key Vault:

**Using the Upload Script (Recommended):**

```bash
# Upload PFX certificate with password
./scripts/helpers/upload-ssl-certificate.sh dev /path/to/astrapia-wildcard.pfx 'MyPassword123'

# Upload PEM certificate (no password)
./scripts/helpers/upload-ssl-certificate.sh dev /path/to/astrapia-wildcard.pem

# Upload to staging environment
./scripts/helpers/upload-ssl-certificate.sh staging /path/to/astrapia-wildcard.pfx 'MyPassword123'
```

The script will:
- Verify the Key Vault exists
- Detect certificate format (PFX or PEM)
- Check for existing certificates
- Upload and verify the certificate
- Display certificate details and expiration

**Manual Upload (Alternative):**

```bash
# Set variables
KEY_VAULT_NAME="nbrly-dev-eastus-kv"
CERT_NAME="astrapia-wildcard"
CERT_FILE="/path/to/astrapia-wildcard.pfx"
CERT_PASSWORD="your-certificate-password"

# Upload certificate to Key Vault
az keyvault certificate import \
  --vault-name "$KEY_VAULT_NAME" \
  --name "$CERT_NAME" \
  --file "$CERT_FILE" \
  --password "$CERT_PASSWORD"

# Verify upload
az keyvault certificate show \
  --vault-name "$KEY_VAULT_NAME" \
  --name "$CERT_NAME" \
  --query "{name:name,enabled:attributes.enabled,expires:attributes.expires}" \
  --output table
```

## Configuration

Custom domain settings are defined in `config/app-config-{env}.json`:

```json
{
  "customDomain": {
    "enabled": true,
    "domainName": "nbrly-dev.astrapia.io",
    "certificateName": "astrapia-wildcard-cert",
    "keyVaultCertificateName": "astrapia-wildcard"
  }
}
```

**Configuration Fields:**

- `enabled`: Enable/disable custom domain (true/false)
- `domainName`: Your custom domain (environment-specific)
- `certificateName`: Name for certificate in Container Apps Environment
- `keyVaultCertificateName`: Name of certificate in Key Vault

## DNS Configuration

Before deploying, you must configure DNS records:

### Required DNS Records

#### 1. CNAME Record (Domain Mapping)

Maps your custom domain to the Container Apps Environment:

```
Name:  nbrly-dev.astrapia.io (or @ for root)
Type:  CNAME
TTL:   3600
Value: <env-default-domain>  (e.g., purple-forest-12345678.eastus.azurecontainerapps.io)
```

#### 2. TXT Record (Domain Validation)

Proves you own the domain:

```
Name:  asuid.nbrly-dev.astrapia.io
Type:  TXT
TTL:   3600
Value: <verification-id>  (obtained from Container Apps Environment)
```

### Getting DNS Values

The deployment script provides the required DNS values:

```bash
./scripts/deploy-ssl.sh dev
```

Output includes:
```
DNS Records to create:
==========================================
CNAME Record:
  Name:  nbrly-dev.astrapia.io
  Type:  CNAME
  Value: purple-forest-12345678.eastus.azurecontainerapps.io

TXT Record (for validation):
  Name:  asuid.nbrly-dev.astrapia.io
  Type:  TXT
  Value: A1B2C3D4E5F6...
==========================================
```

### DNS Provider Configuration

**Azure DNS:**
```bash
# Create DNS zone (if not exists)
az network dns zone create \
  --resource-group dns-rg \
  --name astrapia.io

# Add CNAME record
az network dns record-set cname set-record \
  --resource-group dns-rg \
  --zone-name astrapia.io \
  --record-set-name nbrly-dev \
  --cname purple-forest-12345678.eastus.azurecontainerapps.io

# Add TXT record
az network dns record-set txt add-record \
  --resource-group dns-rg \
  --zone-name astrapia.io \
  --record-set-name asuid.nbrly-dev \
  --value "A1B2C3D4E5F6..."
```

**Cloudflare, GoDaddy, Route53, etc.:**
- Log in to your DNS provider's control panel
- Add the CNAME and TXT records as shown above
- Wait for DNS propagation (typically 5-60 minutes)

### Verify DNS Propagation

```bash
# Check CNAME record
dig nbrly-dev.astrapia.io CNAME +short

# Check TXT record
dig asuid.nbrly-dev.astrapia.io TXT +short

# Alternative using nslookup
nslookup -type=CNAME nbrly-dev.astrapia.io
nslookup -type=TXT asuid.nbrly-dev.astrapia.io
```

## Deployment

### Step 1: Prepare Certificate

Ensure certificate is uploaded to Key Vault (see Prerequisites #3).

### Step 2: Configure DNS

Create CNAME and TXT records in your DNS provider (see DNS Configuration).

### Step 3: Run Deployment Script

```bash
cd sample-app

# Deploy SSL configuration for dev
./scripts/deploy-ssl.sh dev

# The script will:
# 1. Verify infrastructure exists
# 2. Check certificate in Key Vault
# 3. Upload certificate to Container Apps Environment
# 4. Display DNS configuration requirements
# 5. Prompt for DNS confirmation
# 6. Bind custom domain with certificate
# 7. Enable TLS/SSL for all apps
```

### Step 4: Verify Configuration

```bash
# Test HTTPS connection
curl -v https://nbrly-dev.astrapia.io

# Check certificate details
openssl s_client -connect nbrly-dev.astrapia.io:443 -servername nbrly-dev.astrapia.io

# View environment configuration
az containerapp env show \
  --name nbrly-dev-eastus-env \
  --resource-group nbrly-dev-eastus-rg \
  --query "properties.customDomainConfiguration"
```

## Environment-Specific Domains

Each environment has its own subdomain:

| Environment | Custom Domain | Default Domain |
|-------------|---------------|----------------|
| Dev | nbrly-dev.astrapia.io | nbrly-dev-eastus-env.eastus.azurecontainerapps.io |
| Staging | nbrly-staging.astrapia.io | nbrly-staging-eastus-env.eastus.azurecontainerapps.io |
| Prod | nbrly-prod.astrapia.io | nbrly-prod-eastus-env.eastus.azurecontainerapps.io |

All environments use the same wildcard certificate (`*.astrapia.io`).

## Access Patterns

### Without HTTP Routing

Each container app gets its own subdomain:

```
https://<app-name>.nbrly-dev.astrapia.io
```

Example:
```
https://nbrly-dev-eastus-api-ca.nbrly-dev.astrapia.io
```

### With HTTP Routing

Single domain with path-based routing:

```
https://nbrly-dev.astrapia.io/app1
https://nbrly-dev.astrapia.io/app2
https://nbrly-dev.astrapia.io/api
```

See [routing.md](routing.md) for routing configuration.

## Certificate Management

### View Certificates

```bash
# List certificates in environment
az containerapp env certificate list \
  --resource-group nbrly-dev-eastus-rg \
  --name nbrly-dev-eastus-env \
  --output table

# Show certificate details
az containerapp env certificate show \
  --resource-group nbrly-dev-eastus-rg \
  --name nbrly-dev-eastus-env \
  --certificate-name astrapia-wildcard-cert
```

### Update Certificate

When certificate expires or needs renewal:

```bash
# 1. Upload new certificate to Key Vault
az keyvault certificate import \
  --vault-name nbrly-dev-eastus-kv \
  --name astrapia-wildcard \
  --file /path/to/new-certificate.pfx \
  --password "new-password"

# 2. Update Container Apps Environment
./scripts/deploy-ssl.sh dev
```

### Delete Certificate

```bash
az containerapp env certificate delete \
  --resource-group nbrly-dev-eastus-rg \
  --name nbrly-dev-eastus-env \
  --certificate-name astrapia-wildcard-cert
```

## Security Best Practices

### 1. Certificate Storage

- ✅ Store certificates in Azure Key Vault
- ✅ Use system-assigned managed identity for access
- ✅ Enable Key Vault soft delete and purge protection
- ❌ Never commit certificates to source control
- ❌ Never store certificates as plain files

### 2. Certificate Rotation

- Set up certificate expiration alerts (90 days before)
- Use Azure App Service Certificates for auto-renewal
- Test certificate updates in dev/staging first
- Document renewal procedures

### 3. TLS Configuration

- Enforce HTTPS only (no HTTP)
- Use TLS 1.2 or higher
- Disable insecure ciphers
- Enable HSTS (HTTP Strict Transport Security)

### 4. Access Control

- Restrict Key Vault access with RBAC
- Use separate Key Vaults per environment
- Enable Key Vault audit logging
- Monitor certificate access

## Troubleshooting

### Certificate Upload Failed

**Error:** `Certificate not found in Key Vault`

**Solution:**
```bash
# Verify certificate exists
az keyvault certificate show \
  --vault-name nbrly-dev-eastus-kv \
  --name astrapia-wildcard

# Check permissions
az keyvault show \
  --name nbrly-dev-eastus-kv \
  --query properties.accessPolicies
```

### DNS Validation Failed

**Error:** `Domain ownership could not be verified`

**Solution:**
```bash
# Verify TXT record exists
dig asuid.nbrly-dev.astrapia.io TXT +short

# Check TXT record value matches
az containerapp env show \
  --name nbrly-dev-eastus-env \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.customDomainConfiguration.customDomainVerificationId

# Wait for DNS propagation (can take up to 48 hours)
```

### SSL Certificate Not Valid

**Error:** `NET::ERR_CERT_COMMON_NAME_INVALID`

**Solution:**
1. Verify certificate covers the domain:
   ```bash
   openssl x509 -in certificate.pem -text -noout | grep -A1 "Subject Alternative Name"
   ```

2. Ensure wildcard certificate includes subdomain:
   - Certificate: `*.astrapia.io`
   - Domain: `nbrly-dev.astrapia.io` ✅
   - Domain: `api.nbrly-dev.astrapia.io` ❌ (needs `*.*.astrapia.io`)

3. Check certificate expiration:
   ```bash
   az keyvault certificate show \
     --vault-name nbrly-dev-eastus-kv \
     --name astrapia-wildcard \
     --query attributes.expires
   ```

### HTTPS Not Working

**Error:** `Connection refused` or `SSL handshake failed`

**Solution:**
```bash
# 1. Verify custom domain is configured
az containerapp env show \
  --name nbrly-dev-eastus-env \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.customDomainConfiguration.dnsSuffix

# 2. Check certificate binding
az containerapp env certificate list \
  --resource-group nbrly-dev-eastus-rg \
  --name nbrly-dev-eastus-env

# 3. Test with default domain first
curl https://nbrly-dev-eastus-env.eastus.azurecontainerapps.io

# 4. Check DNS resolution
nslookup nbrly-dev.astrapia.io
```

### Certificate Renewal

**Azure App Service Certificate** (Automatic):
- Renews automatically 30 days before expiration
- Sends email notifications
- No action required if Key Vault permissions are correct

**Let's Encrypt or Commercial CA** (Manual):
```bash
# 1. Obtain new certificate
# 2. Import to Key Vault (same name)
az keyvault certificate import \
  --vault-name nbrly-dev-eastus-kv \
  --name astrapia-wildcard \
  --file /path/to/renewed-certificate.pfx

# 3. Container Apps Environment will pick up new certificate automatically
```

## Cost Considerations

- **Azure-managed TLS**: Free (included with Container Apps)
- **Azure App Service Certificate**: ~$75-300/year (auto-renews)
- **Let's Encrypt**: Free (manual renewal every 90 days)
- **Commercial CA**: $50-500+/year depending on validation level

## Related Documentation

- [Deployment Guide](deployment.md)
- [HTTP Routing](routing.md)
- [Configuration Guide](configuration.md)
- [Azure Container Apps Custom Domains](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)

## Reference

### Azure CLI Commands

```bash
# Upload certificate to environment
az containerapp env certificate upload \
  --resource-group <rg> \
  --name <env-name> \
  --certificate-name <cert-name> \
  --certificate-identity "system" \
  --certificate-key-vault-url <kv-cert-id>

# Configure custom domain
az containerapp env update \
  --resource-group <rg> \
  --name <env-name> \
  --dns-suffix <custom-domain> \
  --certificate-identity "system" \
  --certificate-key-vault-url <kv-cert-id>

# List certificates
az containerapp env certificate list \
  --resource-group <rg> \
  --name <env-name>

# Delete certificate
az containerapp env certificate delete \
  --resource-group <rg> \
  --name <env-name> \
  --certificate-name <cert-name>
```

### Configuration Schema

```json
{
  "customDomain": {
    "enabled": boolean,
    "domainName": string,
    "certificateName": string,
    "keyVaultCertificateName": string
  }
}
```
