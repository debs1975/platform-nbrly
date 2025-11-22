# Credentials Folder

This folder contains sensitive credentials required for Azure authentication and SSL certificates.

## Files

### `azure-credentials-dev.cred`
Service Principal credentials for Azure CLI authentication.
- Format: JSON
- Contains: subscriptionId, tenantId, clientId, clientSecret
- Used by: `scripts/helpers/azure-login.sh`

### `astrapiaio.json`
Certificate metadata for the wildcard SSL certificate `*.astrapia.io`.
- Format: JSON
- Contains: Certificate information and metadata

### `astrapiaiofullchain.pfx`
SSL certificate file in PFX format for `*.astrapia.io`.
- Format: PFX (PKCS#12)
- Used for: HTTPS/TLS connections via Application Gateway
- Protection: Password protected (stored in Azure Key Vault)

## Security Notes

⚠️ **IMPORTANT**: These files contain sensitive information and should NEVER be committed to version control.

- All credential files are listed in `.gitignore`
- Store production credentials securely (e.g., Azure Key Vault, GitHub Secrets)
- Rotate credentials regularly
- Use different credentials for different environments (dev/stage/prod)

## Usage

Scripts automatically look for credentials in this folder:
```bash
# Azure login helper automatically uses azure-credentials-dev.cred
source scripts/helpers/azure-login.sh
azure_login
```

## Setup

1. Obtain Service Principal credentials from your Azure administrator
2. Place `azure-credentials-dev.cred` in this folder
3. Ensure SSL certificates are available for HTTPS configuration
4. Verify file permissions (should not be world-readable)

```bash
# Recommended permissions
chmod 600 creds/azure-credentials-dev.cred
chmod 600 creds/astrapiaiofullchain.pfx
```
