# Infrastructure Implementation To-Do List

This file tracks the tasks for setting up the multi-tenant Azure infrastructure.

## Phase 1: Common Infrastructure Setup

- [ ] **Task 1: Create Resource Group**
  - Create the main resource group `astra-dev-eastus-rg`.
- [ ] **Task 2: Setup Networking**
  - Create the VNet `astra-dev-eastus-vnet`.
  - Create subnets for App Gateway, Bastion, and PostgreSQL.
- [ ] **Task 3: Deploy Core Services**
  - Create the Log Analytics Workspace `astra-dev-eastus-law`.
  - Create the Azure Container Registry `astradevacr`.
  - Create the Key Vault `astradeveastuskv`.
- [ ] **Task 4: Upload Wildcard Certificate to Key Vault**
  - Upload the `*.astrapia.io` certificate to the Key Vault.
- [ ] **Task 5: Deploy Application Gateway**
  - Create a Public IP.
  - Deploy the Application Gateway with WAF_v2 SKU.
  - Configure it to use the certificate from Key Vault.

## Phase 2: Tenant Infrastructure Deployment (for `nbrly` and `bloom`)

These tasks should be repeated for each tenant.

### Tenant: nbrly
- [ ] **Task 6: Create Tenant Subnet (`nbrly`)**
  - Create the dedicated subnet `snet-nbrly-dev-cae`.
- [ ] **Task 7: Create Tenant-Specific Resources (`nbrly`)**
  - Create the User-Assigned Managed Identity `nbrly-dev-uami`.
  - Grant the identity `AcrPull` access to the ACR.
- [ ] **Task 8: Deploy PostgreSQL Database (`nbrly`)**
  - Deploy a PostgreSQL Flexible Server.
  - Store the connection string in Key Vault.
- [ ] **Task 9: Deploy Container App Environment (`nbrly`)**
  - Create the internal-only Container App Environment `nbrly-dev-cae`.
- [ ] **Task 10: Deploy Container App (`nbrly`)**
  - Deploy a sample container app `nbrly-dev-app1-ca`.
  - Configure it to use the tenant's managed identity.
- [ ] **Task 11: Configure Application Gateway Routing (`nbrly`)**
  - Add a backend pool, listener for `nbrly-dev.astrapia.io`, and a routing rule.

### Tenant: bloom
- [ ] **Task 6: Create Tenant Subnet (`bloom`)**
  - Create the dedicated subnet `snet-bloom-dev-cae`.
- [ ] **Task 7: Create Tenant-Specific Resources (`bloom`)**
  - Create the User-Assigned Managed Identity `bloom-dev-uami`.
  - Grant the identity `AcrPull` access to the ACR.
- [ ] **Task 8: Deploy PostgreSQL Database (`bloom`)**
  - Deploy a PostgreSQL Flexible Server.
  - Store the connection string in Key Vault.
- [ ] **Task 9: Deploy Container App Environment (`bloom`)**
  - Create the internal-only Container App Environment `bloom-dev-cae`.
- [ ] **Task 10: Deploy Container App (`bloom`)**
  - Deploy a sample container app `bloom-dev-app1-ca`.
  - Configure it to use the tenant's managed identity.
- [ ] **Task 11: Configure Application Gateway Routing (`bloom`)**
  - Add a backend pool, listener for `bloom-dev.astrapia.io`, and a routing rule.

## Phase 3: DNS and Verification

- [ ] **Task 12: Configure DNS**
  - In the `astrapia.io` Azure DNS Zone, create `A` records for `nbrly-dev.astrapia.io` and `bloom-dev.astrapia.io` pointing to the Application Gateway's public IP.
- [ ] **Task 13: End-to-End Verification**
  - Perform `curl` requests to each tenant's domain to verify connectivity.
  - Check logs to ensure traffic is flowing correctly.
