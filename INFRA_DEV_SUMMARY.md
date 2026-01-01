# Development Infrastructure Summary

## Overview
This document summarizes the actual deployed infrastructure resources in the **dev** environment.

## Infrastructure Tracking Files
- **iac-cli/config/infra-dev.json** - Infrastructure provisioning resources (VNet, App Gateway, Key Vault, Container Registry, CAEs)
- **app-gtwy-apps/config/infra-dev.json** - Container App deployment resources

## Deployed Resources

### Subscription & Resource Group
- **Subscription ID**: `984059e7-2907-4273-8569-703dddc5adfa`
- **Resource Group**: `astra-dev-eastus-rg`

### Networking
- **Virtual Network**: `astra-dev-eastus-vnet`
  - **Address Space**: `10.100.0.0/16`
  - **Subnets**:
    - `snet-appgateway`: `10.100.0.0/24`
    - `snet-nbrly-dev-cae`: `10.100.10.0/24`
    - `snet-bloom-dev-cae`: `10.100.11.0/24`

### Application Gateway (Ingress)
- **Name**: `astra-dev-eastus-agw`
- **SKU**: `Standard_v2`
- **Public IP**: `52.146.91.161`
- **Backend Pools**:
  - nbrly: `nbrly-dev-cae.grayfield-aa4022a1.eastus.azurecontainerapps.io`
  - bloom: `bloom-dev-cae.graycliff-28ad9dd7.eastus.azurecontainerapps.io`
- **HTTP Listeners**:
  - nbrly: `nbrly-dev.astrapia.io`
  - bloom: `bloom-dev.astrapia.io`

### Container Registries
- **Name**: `astradeveastusacr`
- **Login Server**: `astradeveastusacr.azurecr.io`

### Key Vault
- **Name**: `astradeveastuskv`
- **Stored Certificates**: `astrapia-io-wildcard-ssl`

### Container App Environments
1. **nbrly-dev-cae**
   - **Default Domain**: `grayfield-aa4022a1.eastus.azurecontainerapps.io`
   - **Static IP**: `10.100.10.122`
   - **Subnet**: `snet-nbrly-dev-cae` (10.100.10.0/24)

2. **bloom-dev-cae**
   - **Default Domain**: `graycliff-28ad9dd7.eastus.azurecontainerapps.io`
   - **Static IP**: `10.100.11.184`
   - **Subnet**: `snet-bloom-dev-cae` (10.100.11.0/24)

### Managed Identities
- **AGW**: `agw-managed-identity` (for Application Gateway)
- **nbrly**: `nbrly-dev-uami` (for nbrly container apps)
- **bloom**: `bloom-dev-uami` (for bloom container apps)

### Private Link Service
- **Name**: `astra-dev-eastus-agw-pls`
- **Visibility**: All
- **Auto Approval**: All

## Notes
- Stage and production infrastructure files are **NOT created** since those environments have not been deployed yet
- Infrastructure tracking files should only be created after actual deployment to capture real resource IDs and properties
- Both infra-dev.json files are consistent and have been validated

## Update Procedure
When stage and prod environments are deployed:
1. Collect actual resource IDs and properties from Azure portal or CLI
2. Create `infra-stage.json` and `infra-prod.json` files with real values
3. Update Container App Environment default domains (currently placeholders in stage/prod configs)
