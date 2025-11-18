# Azure Infrastructure Deployment Guide

This document provides instructions on how to deploy and manage the multi-tenant infrastructure.

## Prerequisites

1.  **Azure CLI:** Ensure you have Azure CLI installed and authenticated.
2.  **jq:** The scripts use `jq` to parse JSON files. Install it using `brew install jq`.
3.  **Permissions:** You need permissions to create resource groups, resources, and role assignments in the target Azure subscription.
4.  **Wildcard Certificate:** A wildcard certificate (`*.astrapia.io`) must be available in PFX format. You will be prompted to upload it to the Key Vault.

## Deployment Steps

The deployment is a two-phase process.

### Phase 1: Deploy Common Infrastructure

This phase provisions the shared resources like the VNet, Key Vault, ACR, and Application Gateway.

1.  Navigate to the `iac-cli/scripts` directory.
2.  Run the common infrastructure deployment script:

    ```bash
    ./01-deploy-common-infra.sh
    ```

3.  **Manual Step: Upload Certificate:** The script will create the Key Vault. You must manually upload your wildcard certificate to it.
    *   Go to the Azure Portal, find the `astradeveastuskv` Key Vault.
    *   Go to the "Certificates" section and click "Generate/Import".
    *   Select "Import", give it the name `astrapia-wildcard-cert`, upload your PFX file, and enter the password.

### Phase 2: Deploy Tenant Infrastructure

This phase provisions the resources for a specific tenant. Repeat these steps for each tenant you want to onboard.

1.  From the `iac-cli/scripts` directory, run the tenant deployment wrapper script, passing the tenant name as an argument.

    **For `nbrly` tenant:**
    ```bash
    ./02-deploy-tenant-infra.sh nbrly
    ```

    **For `bloom` tenant:**
    ```bash
    ./02-deploy-tenant-infra.sh bloom
    ```

The script will automatically call the necessary sub-scripts to create the tenant's resources and configure the Application Gateway routing.

### Phase 3: Configure DNS

After the Application Gateway is deployed and the tenants are configured, you need to point the tenant-specific domains to the Application Gateway's public IP address.

1.  Get the Public IP address of the Application Gateway:
    ```bash
    az network public-ip show \
      --resource-group astra-dev-eastus-rg \
      --name astra-dev-eastus-pip \
      --query "ipAddress" -o tsv
    ```
2.  In your Azure DNS Zone for `astrapia.io`, create `A` records for `nbrly-dev.astrapia.io` and `bloom-dev.astrapia.io` that point to the IP address obtained in the previous step.

## Verification

After completing the deployment and DNS configuration, you can verify the setup by sending requests to the tenant domains:

```bash
curl https://nbrly-dev.astrapia.io
curl https://bloom-dev.astrapia.io
```

You should receive a "Hello from Azure Container Apps" response from each.
