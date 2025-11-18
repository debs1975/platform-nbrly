# Detailed Design & Implementation Plan: Multi-Tenant Azure Container Apps with Application Gateway

This document provides a detailed design and implementation plan for the multi-tenant Azure infrastructure as specified in the `azure-ca-appgtwy.md` guide.

## 1. Overview

The goal is to build a secure, scalable, and multi-tenant infrastructure on Azure using Infrastructure as Code (IaC) principles with Azure CLI. The architecture will host microservices on Azure Container Apps, with a centralized Application Gateway for secure ingress and routing. The design supports multiple tenants from a shared VNet, with logical and network-level isolation for each tenant's resources.

## 2. High-Level Design Decisions

- **Centralized VNet:** A single Virtual Network will serve as the common networking backbone for all tenants, simplifying network management and security.
- **Tenant Isolation with Subnets:** Each tenant's Container App Environment (CAE) will be deployed into a dedicated subnet, providing network-level isolation.
- **Internal-Only Container Apps:** All CAEs will be configured as "internal-only," meaning they are not accessible directly from the public internet. All ingress traffic must flow through the Application Gateway.
- **Shared Ingress with Application Gateway:** A single Application Gateway (WAF_v2 SKU) will act as the secure entry point for all tenants, providing WAF protection, SSL termination, and multi-domain routing.
- **Managed Identities for Security:** User-Assigned Managed Identities will be used for Azure resources (per tenant) to enforce the principle of least privilege and eliminate credential-based authentication.
- **Centralized Secrets Management:** A common Azure Key Vault will securely store all secrets, including the wildcard SSL/TLS certificate and database connection strings.
- **Layered IaC Implementation:** Deployment scripts will be separated into two phases: common infrastructure and tenant-specific infrastructure.

## 3. Network Design

A single VNet will be created with an address space large enough to accommodate all planned subnets.

- **VNet Address Space:** `10.100.0.0/16`
- **Subnet Breakdown:**
  - **Application Gateway Subnet:**
    - **Name:** `snet-appgateway`
    - **Address Prefix:** `10.100.0.0/24`
  - **Azure Bastion Subnet:**
    - **Name:** `AzureBastionSubnet` (This name is required by Azure)
    - **Address Prefix:** `10.100.1.0/26`
  - **PostgreSQL Flexible Server Subnets (using VNet integration):**
    - A dedicated subnet will be delegated for PostgreSQL Flexible Servers.
    - **Name:** `snet-postgres`
    - **Address Prefix:** `10.100.2.0/24`
  - **Tenant Subnets (for Container App Environments):**
    - Each tenant requires a subnet with at least 150 available IPs. A `/24` prefix (251 usable IPs) is suitable.
    - **Tenant 1 (nbrly):** `10.100.10.0/24`
    - **Tenant 2 (bloom):** `10.100.11.0/24`
    - **Tenant 3 (reserved):** `10.100.12.0/24`
    - **Tenant 4 (reserved):** `10.100.13.0/24`
    - **Tenant 5 (reserved):** `10.100.14.0/24`

## 4. Resource Naming Conventions

The following table details the naming for the initial deployment (`dev` environment, `eastus` region).

| Resource Type | Common/Tenant | Naming Pattern | Example Name |
| --- | --- | --- | --- |
| Resource Group | Common | `astra-{{env}}-{{region}}-rg` | `astra-dev-eastus-rg` |
| Virtual Network | Common | `astra-{{env}}-{{region}}-vnet` | `astra-dev-eastus-vnet` |
| Application Gateway | Common | `astra-{{env}}-{{region}}-agw` | `astra-dev-eastus-agw` |
| Public IP (for AGW) | Common | `astra-{{env}}-{{region}}-pip` | `astra-dev-eastus-pip` |
| Key Vault | Common | `astradeveastuskv` | `astradeveastuskv` |
| ACR | Common | `astradevacr` | `astradevacr` |
| Log Analytics | Common | `astra-dev-eastus-law` | `astra-dev-eastus-law` |
| CAE Subnet | Tenant | `snet-{{tenantName}}-{{env}}-cae` | `snet-nbrly-dev-cae` |
| Container App Env | Tenant | `{{tenantName}}-{{env}}-cae` | `nbrly-dev-cae` |
| Managed Identity | Tenant | `{{tenantName}}-{{env}}-uami` | `nbrly-dev-uami` |
| PostgreSQL Server | Tenant | `{{tenantName}}-{{env}}-psql` | `nbrly-dev-psql` |
| Container App | Tenant | `{{tenantName}}-{{env}}-{{appName}}-ca` | `nbrly-dev-app1-ca` |

## 5. Security Design

- **Network Security:**
  - The Application Gateway will have a Web Application Firewall (WAF) policy in `Prevention` mode.
  - Network Security Groups (NSGs) will be associated with subnets to restrict traffic flow. The CAE subnet NSG will only allow inbound traffic from the Application Gateway subnet.
  - All Container App Environments are internal and have no public IP addresses.
- **Identity & Access Management:**
  - A User-Assigned Managed Identity will be created for each tenant.
  - This identity will be granted `AcrPull` role on the common ACR.
  - The Container Apps will be configured to use this identity to pull images.
- **Secrets Management:**
  - The `*.astrapia.io` wildcard certificate will be uploaded to the central Key Vault.
  - The Application Gateway will be configured to reference this certificate from Key Vault using a managed identity.
  - Database credentials for each tenant's PostgreSQL server will be stored as secrets in the Key Vault.
- **Data Protection:**
  - SSL/TLS will be terminated at the Application Gateway, and traffic will be re-encrypted to the backend Container Apps.
  - Data at rest for PostgreSQL and other services will be encrypted by default.

## 6. Directory Structure

The `iac-cli` directory will be organized to separate common infrastructure from tenant-specific configurations and scripts, as requested in the project guidelines.

```
iac-cli/
├── config/
│   ├── parameters-dev.json         # Common parameters for dev
│   ├── bloom/
│   │   └── parameters-dev.json     # Bloom-specific parameters
│   └── nbrly/
│       └── parameters-dev.json     # Nbrly-specific parameters
│
├── scripts/
│   ├── 01-deploy-common-infra.sh   # Deploys all common resources
│   ├── 02-deploy-tenant-infra.sh   # Wrapper script to deploy a specific tenant
│   │
│   ├── helpers/                    # Helper scripts (logging, etc.)
│   │
│   ├── bloom/
│   │   ├── 01-deploy-tenant-resources.sh
│   │   └── 02-configure-routing.sh
│   │
│   └── nbrly/
│       ├── 01-deploy-tenant-resources.sh
│       └── 02-configure-routing.sh
│
└── ... (other directories like creds/, docs/, logs/)
```

## 7. Implementation Plan & To-Do List

The implementation will be broken down into tasks, which will be tracked in a `TODO.md` file.

### Phase 1: Common Infrastructure Setup

- **Task 1: Create Resource Group**
  - Create the main resource group `astra-dev-eastus-rg`.
- **Task 2: Setup Networking**
  - Create the VNet `astra-dev-eastus-vnet`.
  - Create subnets for App Gateway, Bastion, and PostgreSQL.
- **Task 3: Deploy Core Services**
  - Create the Log Analytics Workspace `astra-dev-eastus-law`.
  - Create the Azure Container Registry `astradevacr`.
  - Create the Key Vault `astradeveastuskv`.
- **Task 4: Upload Wildcard Certificate to Key Vault**
  - Manually or via script, upload the `*.astrapia.io` certificate to the Key Vault.
- **Task 5: Deploy Application Gateway**
  - Create a Public IP.
  - Deploy the Application Gateway with WAF_v2 SKU.
  - Configure it to use the certificate from Key Vault. This requires setting up a managed identity for the App Gateway and granting it access to the Key Vault.

### Phase 2: Tenant Infrastructure Deployment

This phase will be executed for each tenant, creating their isolated set of resources.

#### Tenant: nbrly

- **Task 6 (nbrly): Create Tenant Subnet**
  - Create the dedicated subnet `snet-nbrly-dev-cae` with address prefix `10.100.10.0/24`.
- **Task 7 (nbrly): Create Tenant-Specific Resources**
  - Create the User-Assigned Managed Identity `nbrly-dev-uami`.
  - Grant the `nbrly-dev-uami` identity `AcrPull` access to the `astradevacr` container registry.
- **Task 8 (nbrly): Deploy PostgreSQL Database**
  - Deploy PostgreSQL Flexible Server `nbrly-dev-psql`.
  - Store its connection string as a secret named `nbrly-dev-psql-connection-string` in Key Vault.
- **Task 9 (nbrly): Deploy Container App Environment**
  - Create the internal-only Container App Environment `nbrly-dev-cae` in the `snet-nbrly-dev-cae` subnet.
- **Task 10 (nbrly): Deploy Container App**
  - Deploy a sample container app `nbrly-dev-app1-ca`.
  - Configure it to use the `nbrly-dev-uami` managed identity.
  - Inject the database connection string from Key Vault.
- **Task 11 (nbrly): Configure Application Gateway Routing**
  - Add a backend pool for `nbrly-dev-app1-ca`.
  - Add a listener for the domain `nbrly-dev.astrapia.io`.
  - Create a routing rule to connect the listener to the backend pool.

#### Tenant: bloom

- **Task 6 (bloom): Create Tenant Subnet**
  - Create the dedicated subnet `snet-bloom-dev-cae` with address prefix `10.100.11.0/24`.
- **Task 7 (bloom): Create Tenant-Specific Resources**
  - Create the User-Assigned Managed Identity `bloom-dev-uami`.
  - Grant the `bloom-dev-uami` identity `AcrPull` access to the `astradevacr` container registry.
- **Task 8 (bloom): Deploy PostgreSQL Database**
  - Deploy PostgreSQL Flexible Server `bloom-dev-psql`.
  - Store its connection string as a secret named `bloom-dev-psql-connection-string` in Key Vault.
- **Task 9 (bloom): Deploy Container App Environment**
  - Create the internal-only Container App Environment `bloom-dev-cae` in the `snet-bloom-dev-cae` subnet.
- **Task 10 (bloom): Deploy Container App**
  - Deploy a sample container app `bloom-dev-app1-ca`.
  - Configure it to use the `bloom-dev-uami` managed identity.
  - Inject the database connection string from Key Vault.
- **Task 11 (bloom): Configure Application Gateway Routing**
  - Add a backend pool for `bloom-dev-app1-ca`.
  - Add a listener for the domain `bloom-dev.astrapia.io`.
  - Create a routing rule to connect the listener to the backend pool.

### Phase 3: DNS and Verification

- **Task 12: Configure DNS**
  - In the `astrapia.io` Azure DNS Zone, create an `A` record for each tenant's domain pointing to the Application Gateway's public IP.
- **Task 13: End-to-End Verification**
  - Perform `curl` requests to each tenant's domain.
  - Verify that the request is successful and returns the expected response from the correct container app.
  - Check Application Gateway and Container App logs for any errors.
