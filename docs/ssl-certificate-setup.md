# SSL/TLS Certificate Setup for Container Apps

## Overview

This guide explains how to configure custom domains and SSL/TLS certificates for Azure Container Apps in the nbrly project.

## Architecture

```
Certificate Flow:
┌─────────────────────┐
│ Local PFX File      │
└──────────┬──────────┘
           │ Upload
           ▼
┌─────────────────────┐
│ Azure Key Vault     │
│ (Secure Storage)    │
└──────────┬──────────┘
           │ Download (via script)
           ▼
┌─────────────────────┐
│ Container Apps Env  │
│ (Certificate Store) │
└──────────┬──────────┘
           │ Bind
           ▼
┌─────────────────────┐
│ Individual Apps     │
│ (HTTPS Endpoints)   │
└─────────────────────┘
```

## Step-by-Step Guide

### Step 1: Prepare Certificate

Ensure you have a valid SSL certificate in PFX format:

```bash
# If you have separate .crt and .key files, convert to PFX
openssl pkcs12 -export \
  -out wildcard-mycompany-com.pfx \
  -inkey private-key.key \
  -in certificate.crt \
  -password pass:YourPassword
```

### Step 2: Update Configuration

Edit `iac-cli/config/parameters-dev.json`:

```json
{
  "customDomain": {
    "enabled": true,
    "domainName": "mycompany.com",
    "certificateName": "wildcard-mycompany-com",
    "keyVaultCertificateName": "wildcard-mycompany-com",
    "certificateFileName": "wildcard-mycompany-com.pfx",
    "certificatePasswordSecret": "cert-password"
  }
}
```

### Step 3: Store Certificate Password (Optional)

If your certificate is password-protected, store the password in Key Vault:

```bash
az keyvault secret set \
  --vault-name nbrlydeveastuskv \
  --name cert-password \
  --value 'YourCertificatePassword'
```

### Step 4: Place Certificate File

```bash
# Create cred directory if it doesn't exist
mkdir -p iac-cli/cred

# Copy certificate file
cp /path/to/wildcard-mycompany-com.pfx iac-cli/cred/
```

### Step 5: Deploy SSL Configuration

```bash
cd iac-cli
./scripts/06-deploy-ssl.sh dev
```

This script will:
1. ✅ Check if certificate exists in Key Vault
2. ✅ Upload certificate to Key Vault (if not exists)
3. ✅ Download certificate from Key Vault
4. ✅ Upload certificate to Container Apps Environment
5. ✅ Provide DNS configuration instructions

### Step 6: Configure DNS

Add the following DNS records in your domain provider:

**CNAME Record:**
```
Type: CNAME
Name: api (or desired subdomain)
Value: <app-fqdn> (provided by script)
TTL: 3600
```

**TXT Record (for verification):**
```
Type: TXT
Name: asuid.api.mycompany.com
Value: <verification-id> (provided by script)
TTL: 3600
```

### Step 7: Bind Certificate to Container App

```bash
cd sample-app
./scripts/bind-custom-domain.sh dev api.mycompany.com
```

This script will:
1. ✅ Validate prerequisites
2. ✅ Check DNS propagation
3. ✅ Add custom hostname to Container App
4. ✅ Bind SSL certificate
5. ✅ Verify configuration

### Step 8: Verify

```bash
# Test HTTPS endpoint
curl -I https://api.mycompany.com

# Check SSL certificate
openssl s_client -connect api.mycompany.com:443 -servername api.mycompany.com

# View certificate details
az containerapp env certificate list \
  --resource-group nbrly-dev-eastus-rg \
  --name nbrly-dev-eastus-cae \
  --output table
```

## Alternative: Azure-Managed Certificates (Free)

If you don't want to manage your own certificates, Azure can provide free, auto-renewing certificates:

### Configuration

```json
{
  "customDomain": {
    "enabled": false,
    "certificateName": ""
  }
}
```

### Bind with Managed Certificate

```bash
# Add hostname
az containerapp hostname add \
  --resource-group nbrly-dev-eastus-rg \
  --name nbrly-dev-eastus-app-ca \
  --hostname api.mycompany.com

# Bind with Azure-managed certificate
az containerapp hostname bind \
  --resource-group nbrly-dev-eastus-rg \
  --name nbrly-dev-eastus-app-ca \
  --hostname api.mycompany.com \
  --environment nbrly-dev-eastus-cae \
  --validation-method CNAME
```

## Troubleshooting

### Certificate Not Found in Key Vault

```bash
# List all certificates
az keyvault certificate list \
  --vault-name nbrlydeveastuskv \
  --output table

# Manually import certificate
az keyvault certificate import \
  --vault-name nbrlydeveastuskv \
  --name wildcard-mycompany-com \
  --file wildcard-mycompany-com.pfx \
  --password 'YourPassword'
```

### DNS Not Propagating

```bash
# Check DNS propagation
dig api.mycompany.com CNAME
nslookup api.mycompany.com

# Use online tools
# https://dnschecker.org
# https://www.whatsmydns.net
```

### Certificate Binding Failed

```bash
# Check certificate in environment
az containerapp env certificate list \
  --name nbrly-dev-eastus-cae \
  --resource-group nbrly-dev-eastus-rg \
  --output table

# Re-upload certificate
./scripts/06-deploy-ssl.sh dev
```

### HTTPS Not Working

```bash
# Check Container App ingress
az containerapp show \
  --name nbrly-dev-eastus-app-ca \
  --resource-group nbrly-dev-eastus-rg \
  --query properties.configuration.ingress

# Verify hostname binding
az containerapp hostname list \
  --name nbrly-dev-eastus-app-ca \
  --resource-group nbrly-dev-eastus-rg \
  --output table
```

## Security Best Practices

✅ **Certificate Storage**: Always store certificates in Azure Key Vault  
✅ **Access Control**: Use Managed Identity for Key Vault access  
✅ **Password Management**: Store certificate passwords as Key Vault secrets  
✅ **File Cleanup**: Scripts automatically delete temporary certificate files  
✅ **TLS Version**: Container Apps enforces TLS 1.2+  
✅ **Certificate Rotation**: Update certificate in Key Vault, then re-run deploy script  

## Certificate Renewal Process

When your certificate is about to expire:

```bash
# 1. Upload new certificate to cred directory
cp /path/to/new-wildcard-mycompany-com.pfx iac-cli/cred/

# 2. Delete old certificate from Key Vault
az keyvault certificate delete \
  --vault-name nbrlydeveastuskv \
  --name wildcard-mycompany-com

# 3. Re-run SSL deployment
cd iac-cli
./scripts/06-deploy-ssl.sh dev

# 4. Certificate will be automatically re-bound to existing Container Apps
```

## Environment-Specific Configuration

### Development
- Use self-signed certificates or Let's Encrypt
- Azure-managed certificates recommended

### Staging
- Use production-like certificates
- Same domain structure as production

### Production
- Use purchased wildcard certificates
- Enable certificate monitoring and alerts
- Set up automated renewal reminders

## Quick Reference

| Command | Description |
|---------|-------------|
| `./scripts/06-deploy-ssl.sh dev` | Deploy SSL to Container Apps Environment |
| `./scripts/bind-custom-domain.sh dev api.domain.com` | Bind certificate to app |
| `az containerapp env certificate list` | List all certificates |
| `az containerapp hostname list` | List all hostnames for an app |
| `openssl s_client -connect domain.com:443` | Verify SSL certificate |

## Related Documentation

- [Azure Container Apps Custom Domains](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates)
- [Azure Key Vault Certificates](https://learn.microsoft.com/en-us/azure/key-vault/certificates/)
- [Azure Container Apps Ingress](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
