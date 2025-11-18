# Credentials Directory

This directory contains Azure Service Principal credentials for automated deployment.

## Setup Instructions

### Option 1: Copy from iac-cli

If you already have credentials in `iac-cli/creds/azure-credentials-dev.cred`, copy them here:

```bash
cp ../../iac-cli/creds/azure-credentials-dev.cred ./azure-credentials-dev.cred
```

### Option 2: Create New Credentials File

Create a file named `azure-credentials-dev.cred` with the following structure:

```json
{
  "subscriptionId": "YOUR_SUBSCRIPTION_ID",
  "tenantId": "YOUR_TENANT_ID",
  "clientId": "YOUR_CLIENT_ID",
  "clientSecret": "YOUR_CLIENT_SECRET"
}
```

### Security Notes

- ⚠️ **NEVER commit credentials to version control**
- This file is ignored by `.gitignore` in the parent directory
- Use Azure Key Vault for production deployments
- Rotate credentials regularly

### Obtaining Credentials

Create a Service Principal if you don't have one:

```bash
az ad sp create-for-rbac \
  --name "nbrly-dev-sp" \
  --role Contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID
```

The output will contain the credentials you need.

---

**For isolated app-gtway-apps deployment**, this directory allows the application suite to run independently without requiring `iac-cli/creds` to be present.
