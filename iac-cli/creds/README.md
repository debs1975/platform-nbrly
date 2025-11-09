# Azure Credentials Management

## Overview
This directory contains Azure authentication credentials for deployment automation. **All credential files (`.cred`) are automatically excluded from version control.**

## Setup Instructions

### 1. Create Azure Service Principal

You need a Service Principal to authenticate with Azure non-interactively:

```bash
# Option 1: Create service principal with Contributor role on subscription
az ad sp create-for-rbac \
  --name "sp-nbrly-dev-deployer" \
  --role Contributor \
  --scopes /subscriptions/{your-subscription-id}

# Option 2: Create service principal with Contributor role on specific resource group
az ad sp create-for-rbac \
  --name "sp-nbrly-dev-deployer" \
  --role Contributor \
  --scopes /subscriptions/{your-subscription-id}/resourceGroups/nbrly-dev-eastus-rg
```

The output will look like:
```json
{
  "appId": "12345678-1234-1234-1234-123456789abc",
  "displayName": "sp-nbrly-dev-deployer",
  "password": "your-secret-here",
  "tenant": "87654321-4321-4321-4321-abcdef123456"
}
```

**Save these values securely!**

### 2. Grant Service Principal Permissions

The service principal needs **User Access Administrator** role to assign RBAC roles during deployment:

```bash
# Option 1: Resource Group scope (recommended - least privilege)
./scripts/helpers/grant-sp-permissions.sh dev resourcegroup

# Option 2: Subscription scope (broader permissions)
./scripts/helpers/grant-sp-permissions.sh dev subscription
```

**What this grants:**
- ✅ **Contributor** - Create and manage Azure resources
- ✅ **User Access Administrator** - Assign RBAC roles to managed identities and Key Vault

**When to run:**
- ⚠️ **Required** before first deployment
- ⚠️ When you see `AuthorizationFailed` errors during `02-deploy-security.sh`
- ⚠️ After creating a new service principal

**Who can run this:**
- You must be logged in with an account that has **Owner** or **User Access Administrator** at the chosen scope
- Typically your personal Azure account with admin rights

```bash
# Login with admin account
az login

# Run the permission script
./scripts/helpers/grant-sp-permissions.sh dev resourcegroup

# Verify permissions were granted
az role assignment list --assignee {clientId} --output table
```

### 3. Create Credential File

```bash
# Copy the example template
cp creds/azure-credentials.example.json creds/azure-credentials-dev.cred

# Edit with your actual credentials
vi creds/azure-credentials-dev.cred
```

**File format** (`azure-credentials-dev.cred`):
```json
{
  "subscriptionId": "your-subscription-id",
  "tenantId": "tenant-id-from-sp-output",
  "clientId": "appId-from-sp-output",
  "clientSecret": "password-from-sp-output",
  "environment": "dev"
}
```

**Mapping from Service Principal output:**
- `subscriptionId` → Your Azure subscription ID (run `az account show --query id -o tsv`)
- `tenantId` → `tenant` from service principal output
- `clientId` → `appId` from service principal output
- `clientSecret` → `password` from service principal output
- `environment` → `dev`, `staging`, or `prod`

### 4. Set Appropriate Permissions

**macOS/Linux:**
```bash
chmod 600 creds/*.cred
```

**Windows PowerShell:**
```powershell
icacls creds\*.cred /inheritance:r /grant:r "$env:USERNAME:(R)"
```

### 5. Verify Setup

```bash
# Test authentication
cd scripts
./helpers/test-azure-login.sh dev
```

Expected output:
```
✅ Successfully logged into Azure
   Active subscription: Your Subscription Name
```

## File Naming Convention

Create separate credential files for each environment:

- `azure-credentials-dev.cred` - Development environment
- `azure-credentials-staging.cred` - Staging environment
- `azure-credentials-prod.cred` - Production environment

## Security Best Practices

### ✅ DO:
- Keep credential files in `creds/` directory only
- Use unique service principals per environment
- Rotate secrets every 90 days (recommended)
- Set least-privilege RBAC roles (Contributor on specific RG is better than subscription-wide)
- Restrict file permissions to owner-only (`chmod 600`)
- Store production credentials separately from dev/staging
- Use Azure Key Vault for additional secret management

### ❌ DON'T:
- Commit `.cred` files to Git (they're automatically ignored)
- Share credential files via email, Slack, or other insecure channels
- Use the same service principal across all environments
- Store credentials in code, environment variables, or scripts
- Use Owner or admin roles unless absolutely necessary
- Hard-code credentials anywhere

## Environment Variables (Alternative)

If you prefer environment variables over credential files, you can set:

```bash
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
```

The login script will check for these variables if no credential file is found.

## Troubleshooting

### "Credential file not found"
```bash
# Verify file exists
ls -la creds/

# Check naming convention (must match pattern)
# Correct: azure-credentials-dev.cred
# Wrong: credentials-dev.cred, azure-dev.cred
```

### "Authentication failed"
```bash
# Test service principal manually
az login --service-principal \
  --username {clientId} \
  --password {clientSecret} \
  --tenant {tenantId}

# Verify subscription access
az account show

# Check service principal hasn't expired
az ad sp show --id {clientId}
```

### "Permission denied"
```bash
# Fix file permissions (macOS/Linux)
chmod 600 creds/*.cred

# Windows: ensure you're the only user with read access
```

### "Invalid JSON format"
```bash
# Validate JSON syntax
jq . creds/azure-credentials-dev.cred

# Check for:
# - Missing quotes around values
# - Missing commas between fields
# - Extra commas after last field
```

## Emergency: Credential Rotation

If credentials are compromised:

```bash
# 1. Disable the service principal immediately
az ad sp update --id {clientId} --set accountEnabled=false

# 2. Create new service principal
az ad sp create-for-rbac \
  --name "sp-nbrly-{env}-deployer-new" \
  --role Contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/{rg-name}

# 3. Update credential files with new values
vi creds/azure-credentials-{env}.cred

# 4. Test new credentials
./scripts/helpers/test-azure-login.sh {env}

# 5. Delete old service principal
az ad sp delete --id {old-clientId}

# 6. Notify team that credentials were rotated
```

## CI/CD Integration

For GitHub Actions, Azure DevOps, or other CI/CD systems:

**GitHub Actions:**
```yaml
- name: Azure Login
  uses: azure/login@v1
  with:
    creds: ${{ secrets.AZURE_CREDENTIALS }}
```

**Azure DevOps:**
Use Azure Resource Manager service connections instead of credential files.

## Files in This Directory

```
creds/
├── .gitkeep                           # Ensures directory is tracked
├── README.md                          # This file
├── azure-credentials.example.json    # Template for credential files
├── azure-credentials-dev.cred        # Development credentials (IGNORED by Git)
├── azure-credentials-staging.cred    # Staging credentials (IGNORED by Git)
└── azure-credentials-prod.cred       # Production credentials (IGNORED by Git)
```

## Verification Checklist

Before running deployments:

- [ ] Service principal created with appropriate permissions
- [ ] Credential file created from template
- [ ] All required fields populated (subscriptionId, tenantId, clientId, clientSecret)
- [ ] File permissions set to 600 (owner read-write only)
- [ ] File NOT shown in `git status` (should be ignored)
- [ ] Authentication tested with `test-azure-login.sh`
- [ ] Correct subscription shown after login

## Related Documentation
- [Azure Service Principal Authentication](https://learn.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli)
- [Azure RBAC Best Practices](https://learn.microsoft.com/en-us/azure/role-based-access-control/best-practices)
- [Main README](../README.md)
- [Git Ignore Strategy](../.gitignore-guide.md)

## Support

For issues with authentication setup:
1. Check the Troubleshooting section above
2. Review Azure CLI login logs: `az account list --output table`
3. Verify service principal permissions in Azure Portal
4. Contact your Azure administrator if permission issues persist
