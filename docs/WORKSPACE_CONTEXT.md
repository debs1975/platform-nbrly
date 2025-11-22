# Workspace Context - Platform NBRLY

**Repository**: `platform-nbrly`  
**Owner**: debs1975  
**Branch**: `feature-appgtwy`  
**Last Updated**: 2025-01-21  
**Purpose**: Multi-tenant Azure Container Apps infrastructure with Application Gateway

---

## Table of Contents

- [1. Project Overview](#1-project-overview)
- [2. Architecture & Design](#2-architecture--design)
- [3. Directory Structure](#3-directory-structure)
- [4. Infrastructure as Code (IaC)](#4-infrastructure-as-code-iac)
- [5. Naming Conventions](#5-naming-conventions)
- [6. Configuration System](#6-configuration-system)
- [7. Deployment Scripts](#7-deployment-scripts)
- [8. Security Model](#8-security-model)
- [9. Recent Work & Changes](#9-recent-work--changes)
- [10. Key Documentation References](#10-key-documentation-references)
- [11. Continuation Guidelines](#11-continuation-guidelines)

---

## 1. Project Overview

### 1.1 Project Description

Platform NBRLY is a **secure, scalable multi-tenant Azure infrastructure** built with Infrastructure as Code (IaC) principles using Azure CLI. The project is designed to host multiple client applications (tenants) on shared infrastructure while maintaining strong isolation between tenants.

### 1.2 Technology Stack

- **Cloud Provider**: Microsoft Azure
- **Infrastructure**: Azure Container Apps, Application Gateway (WAF_v2), Virtual Network
- **Database**: Azure PostgreSQL Flexible Server (per tenant)
- **Container Registry**: Azure Container Registry (ACR)
- **Secrets Management**: Azure Key Vault
- **Monitoring**: Log Analytics Workspace, Application Insights
- **IaC Tool**: Bash scripts with Azure CLI
- **Application Framework**: Python FastAPI (for sample apps)

### 1.3 Multi-Tenancy Model

- **Common Infrastructure**: Shared VNet, Application Gateway, ACR, Key Vault, Log Analytics
- **Tenant Isolation**: Each tenant has:
  - Dedicated subnet within shared VNet
  - Isolated Container App Environment (CAE)
  - Dedicated PostgreSQL database
  - User-Assigned Managed Identity (UAMI)
  - Custom domain (e.g., `nbrly-dev.astrapia.io`, `bloom-dev.astrapia.io`)
- **Designed for**: 5 tenants (currently implementing 2: `nbrly` and `bloom`)

### 1.4 Key Design Principles

✅ **Security-First**: Managed identities, Key Vault secrets, private endpoints  
✅ **Network Isolation**: Internal-only Container Apps, VNet integration, NSG rules  
✅ **Scalability**: Container Apps auto-scale 0→N based on demand  
✅ **Multi-Environment**: Support for dev, stage, prod environments  
✅ **Centralized Ingress**: Single Application Gateway with SSL/TLS termination  
✅ **Azure Well-Architected**: Follows reliability, security, cost optimization, operational excellence, performance efficiency pillars

---

## 2. Architecture & Design

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │  Application Gateway │ (Public IP, WAF_v2, SSL/TLS)
            │  *.astrapia.io cert  │
            └──────────┬───────────┘
                       │
         ┌─────────────┴─────────────┐
         │                           │
         ▼                           ▼
┌────────────────────┐    ┌────────────────────┐
│  nbrly-dev.        │    │  bloom-dev.        │
│  astrapia.io       │    │  astrapia.io       │
└─────────┬──────────┘    └─────────┬──────────┘
          │                         │
          ▼                         ▼
┌──────────────────────┐  ┌──────────────────────┐
│ NBRLY CAE (Internal) │  │ BLOOM CAE (Internal) │
│ Subnet: 10.100.10/24 │  │ Subnet: 10.100.11/24 │
├──────────────────────┤  ├──────────────────────┤
│ ► Container App 1    │  │ ► Container App 1    │
│ ► Container App 2    │  │ ► Container App 2    │
└──────────┬───────────┘  └──────────┬───────────┘
           │                         │
           ▼                         ▼
    ┌──────────────┐         ┌──────────────┐
    │ PostgreSQL   │         │ PostgreSQL   │
    │ nbrly-dev    │         │ bloom-dev    │
    └──────────────┘         └──────────────┘
```

### 2.2 Network Design

**VNet Address Space**: `10.100.0.0/16`

| Subnet Name | Address Prefix | Purpose | Capacity |
|-------------|----------------|---------|----------|
| `snet-appgateway` | `10.100.0.0/24` | Application Gateway | 251 IPs |
| `AzureBastionSubnet` | `10.100.1.0/26` | Azure Bastion | 59 IPs |
| `snet-postgres` | `10.100.2.0/24` | PostgreSQL Flexible Servers | 251 IPs |
| `snet-nbrly-dev-cae` | `10.100.10.0/24` | NBRLY Container Apps | 251 IPs |
| `snet-bloom-dev-cae` | `10.100.11.0/24` | BLOOM Container Apps | 251 IPs |
| Reserved Tenant 3 | `10.100.12.0/24` | Future tenant | 251 IPs |
| Reserved Tenant 4 | `10.100.13.0/24` | Future tenant | 251 IPs |
| Reserved Tenant 5 | `10.100.14.0/24` | Future tenant | 251 IPs |

### 2.3 Request Flow

1. **DNS Resolution**: `nbrly-dev.astrapia.io` → Application Gateway Public IP
2. **Application Gateway**: 
   - Terminates SSL/TLS with wildcard certificate `*.astrapia.io`
   - Routes based on domain to appropriate backend pool
   - Re-encrypts traffic to backend
3. **Container App Environment**: Routes to specific Container App based on path
4. **Container App**: Handles request and responds

### 2.4 Resource Layers

**Layer 1: Common Infrastructure**
- Resource Group
- Virtual Network with subnets
- Application Gateway + Public IP
- Azure Container Registry (ACR)
- Key Vault
- Log Analytics Workspace

**Layer 2: Tenant Infrastructure** (per tenant)
- Dedicated subnet for Container App Environment
- User-Assigned Managed Identity (UAMI)
- PostgreSQL Flexible Server
- Container App Environment (internal-only)
- Container Apps (1-N per tenant)
- Application Gateway routing rules

---

## 3. Directory Structure

### 3.1 Repository Layout

```
nbrly/
├── .github/                          # GitHub-specific configuration
│   └── instructions/                 # Project guidelines and design docs
│       ├── project-description.instructions.md
│       ├── azure-ca-appgtwy-detail-design.instructions.md
│       ├── directory-structure.instructions.md
│       ├── iac-naming-convention.instructions.md
│       ├── capacity-container-size-analysis.instructions.md
│       └── shell.instructions.md
│
├── docs/                             # Project documentation (ALWAYS place docs here)
│   ├── DEPLOYMENT_CHANGES.md         # Recent PROJECT parameter changes
│   ├── deployment-guide.md           # Deployment instructions
│   ├── ssl-certificate-setup.md      # SSL/TLS certificate guide
│   ├── azure-ca-appgtwy-imp-plan.md  # Implementation plan
│   └── WORKSPACE_CONTEXT.md          # This file
│
├── iac-cli/                          # Infrastructure as Code (IaC)
│   ├── config/                       # Configuration files
│   │   ├── parameters-dev.json       # Common dev environment config
│   │   ├── parameters-stage.json     # Common stage environment config
│   │   ├── parameters-prod.json      # Common prod environment config
│   │   ├── infra-dev.json            # Dev resource tracking (NEW)
│   │   ├── infra-stage.json          # Stage resource tracking (NEW)
│   │   ├── infra-prod.json           # Prod resource tracking (NEW)
│   │   ├── .generated/               # Auto-generated deployment state
│   │   │   ├── generated-infra-dev.json
│   │   │   ├── generated-infra-stage.json
│   │   │   └── generated-infra-prod.json
│   │   ├── nbrly/                    # NBRLY tenant config
│   │   │   ├── parameters-dev.json
│   │   │   ├── parameters-stage.json
│   │   │   └── parameters-prod.json
│   │   └── bloom/                    # BLOOM tenant config
│   │       ├── parameters-dev.json
│   │       ├── parameters-stage.json
│   │       └── parameters-prod.json
│   │
│   ├── creds/                        # Credentials (NOT committed to git)
│   │   ├── azure-credentials.example.json
│   │   ├── azure-credentials-dev.cred
│   │   ├── astrapiaio.json           # DNS zone credentials
│   │   └── README.md
│   │
│   ├── scripts/                      # Deployment scripts
│   │   ├── 00-deploy-all.sh          # Main orchestration script
│   │   ├── 01-deploy-common-infra.sh # Deploy shared infrastructure
│   │   ├── 02-deploy-tenant-infra.sh # Tenant deployment wrapper
│   │   ├── helpers/                  # Utility scripts
│   │   │   ├── azure-login.sh
│   │   │   └── logging.sh
│   │   ├── nbrly/                    # NBRLY tenant scripts
│   │   │   ├── 01-deploy-tenant-resources.sh
│   │   │   └── 02-configure-routing.sh
│   │   ├── bloom/                    # BLOOM tenant scripts
│   │   │   ├── 01-deploy-tenant-resources.sh
│   │   │   └── 02-configure-routing.sh
│   │   └── utils/                    # Additional utilities
│   │
│   ├── logs/                         # Execution logs
│   └── docs/                         # IaC-specific documentation
│
├── app-gtway-apps-previous/          # Previous implementation (reference)
│   ├── nbrly/                        # NBRLY FastAPI apps
│   │   ├── nbapp1/
│   │   └── nbapp2/
│   ├── bloom/                        # BLOOM FastAPI apps
│   │   ├── bmapp1/
│   │   └── bmapp2/
│   └── scripts/                      # Build and deployment scripts
│
├── sample-app/                       # Sample applications for testing
│   ├── main_app1.py
│   ├── main_app2.py
│   ├── Dockerfile.app1
│   └── Dockerfile.app2
│
├── logs/                             # Application logs
│
├── IMPLEMENTATION_SUMMARY.md         # Summary of app implementations
├── ISOLATION_IMPLEMENTATION_REPORT.md
├── QUICK_START_GUIDE.md
├── TODO.md                           # Task tracking
└── README.md                         # Main project README
```

### 3.2 Important Directory Rules

- **docs/**: ALWAYS place documentation here (not in other folders)
- **iac-cli/config/**: Configuration parameters
- **iac-cli/creds/**: Sensitive files (certificates, secrets) - NOT committed to git
- **iac-cli/scripts/**: All IaC bash scripts
- **app-gtway-apps/**: Sample applications (isolated, can be extracted independently)

---

## 4. Infrastructure as Code (IaC)

### 4.1 IaC Principles

- **Declarative Configuration**: All parameters in JSON files
- **Idempotent Scripts**: Safe to run multiple times
- **Layered Deployment**: Common → Tenant infrastructure
- **Environment-Aware**: Separate configs for dev/stage/prod
- **Resource Tracking**: Automatic tracking in `infra-{ENV}.json`

### 4.2 Script Hierarchy

```
00-deploy-all.sh <project> [env]
├── 01-deploy-common-infra.sh <project> [env]
│   ├── Creates: Resource Group
│   ├── Creates: VNet with subnets
│   ├── Creates: Log Analytics Workspace
│   ├── Creates: Azure Container Registry
│   ├── Creates: Key Vault
│   ├── Creates: Public IP
│   └── Creates: Application Gateway
│
└── 02-deploy-tenant-infra.sh <tenant> <project> [env]
    ├── nbrly/01-deploy-tenant-resources.sh <project> [env]
    │   ├── Creates: Tenant subnet
    │   ├── Creates: User-Assigned Managed Identity
    │   ├── Creates: PostgreSQL Flexible Server
    │   ├── Creates: Container App Environment
    │   └── Creates: Container App
    │
    └── nbrly/02-configure-routing.sh <project> [env]
        ├── Creates: Backend pool
        ├── Creates: HTTP settings
        ├── Creates: HTTPS listener
        └── Creates: Routing rule
```

### 4.3 Key Scripts Overview

#### `00-deploy-all.sh`
**Purpose**: Main orchestration script  
**Usage**: `./00-deploy-all.sh <project> [dev|stage|prod]`  
**Example**: `./00-deploy-all.sh astra dev`  
**What it does**:
- Validates PROJECT and ENV parameters
- Calls `01-deploy-common-infra.sh` with PROJECT and ENV
- Calls `02-deploy-tenant-infra.sh` for nbrly tenant
- Calls `02-deploy-tenant-infra.sh` for bloom tenant

#### `01-deploy-common-infra.sh`
**Purpose**: Deploy shared infrastructure  
**Usage**: `./01-deploy-common-infra.sh <project> [dev|stage|prod]`  
**Example**: `./01-deploy-common-infra.sh astra dev`  
**What it does**:
- Loads `parameters-{env}.json` configuration
- **Prints inferred resource names** before any creation
- Creates Resource Group, VNet, ACR, Key Vault, Log Analytics, Application Gateway
- **Tracks created resources** in `infra-{env}.json` after each creation

**Inferred Variables Printed**:
```
Project:              astra
Environment:          dev
Region:               eastus
Resource Group:       astra-dev-eastus-rg
VNet:                 astra-dev-eastus-vnet
VNet Address Prefix:  10.100.0.0/16
App Gateway:          astra-dev-eastus-agw
Public IP:            astra-dev-eastus-pip
Key Vault:            astradeveastuskv
Container Registry:   astradeveastusacr
Log Analytics:        astra-dev-eastus-law
AGW Managed Identity: agw-managed-identity
```

#### `02-deploy-tenant-infra.sh`
**Purpose**: Wrapper to deploy tenant-specific infrastructure  
**Usage**: `./02-deploy-tenant-infra.sh <tenant> <project> [dev|stage|prod]`  
**Example**: `./02-deploy-tenant-infra.sh nbrly astra dev`  
**What it does**:
- Calls `{tenant}/01-deploy-tenant-resources.sh` with PROJECT and ENV
- Calls `{tenant}/02-configure-routing.sh` with PROJECT and ENV

#### `nbrly/01-deploy-tenant-resources.sh` (and `bloom/01-deploy-tenant-resources.sh`)
**Purpose**: Deploy tenant-specific resources  
**Usage**: `./01-deploy-tenant-resources.sh <project> [dev|stage|prod]`  
**Example**: `./01-deploy-tenant-resources.sh astra dev`  
**What it does**:
- Loads common and tenant configuration
- **Prints inferred tenant resource names** before creation
- Creates tenant subnet, UAMI, PostgreSQL, Container App Environment, Container App
- **Tracks tenant resources** in `infra-{env}.json` under `resources.tenants.{tenantName}`

**Inferred Tenant Variables Printed**:
```
Project:              astra
Tenant:               nbrly
Environment:          dev
Region:               eastus
CAE Subnet:           snet-nbrly-dev-cae
CAE Subnet Prefix:    10.100.10.0/24
Container App Env:    nbrly-dev-cae
Managed Identity:     nbrly-dev-uami
PostgreSQL Server:    nbrly-dev-psql
Container App:        nbrly-dev-app1-ca
Domain Name:          nbrly-dev.astrapia.io
```

#### `nbrly/02-configure-routing.sh` (and `bloom/02-configure-routing.sh`)
**Purpose**: Configure Application Gateway routing for tenant  
**Usage**: `./02-configure-routing.sh <project> [dev|stage|prod]`  
**Example**: `./02-configure-routing.sh astra dev`  
**What it does**:
- Creates Application Gateway backend pool for tenant
- Configures HTTP settings
- Creates HTTPS listener for tenant domain
- Creates routing rule from listener to backend pool

### 4.4 Helper Scripts

#### `helpers/azure-login.sh`
**Purpose**: Handle Azure authentication  
**Logic**:
- Checks for `creds/azure-credentials-{env}.cred` file
- If found: Uses Service Principal authentication
- If not found: Falls back to interactive `az login`

#### `helpers/logging.sh`
**Purpose**: Standardized logging functions  
**Functions**:
- `log_info()`: Informational messages
- `log_success()`: Success messages
- `log_error()`: Error messages
- `log_warning()`: Warning messages

---

## 5. Naming Conventions

### 5.1 Naming Pattern

**Common Infrastructure**: `{project}-{env}-{region}-{resourceType}`  
**Tenant Infrastructure**: `{tenantName}-{env}-{resourceName}-{resourceType}` or `{tenantName}-{env}-{resourceType}`

### 5.2 Resource Name Examples

| Resource Type | Common/Tenant | Example Name | Pattern |
|---------------|---------------|--------------|---------|
| Resource Group | Common | `astra-dev-eastus-rg` | `{project}-{env}-{region}-rg` |
| Virtual Network | Common | `astra-dev-eastus-vnet` | `{project}-{env}-{region}-vnet` |
| App Gateway | Common | `astra-dev-eastus-agw` | `{project}-{env}-{region}-agw` |
| Public IP | Common | `astra-dev-eastus-pip` | `{project}-{env}-{region}-pip` |
| Key Vault | Common | `astradeveastuskv` | `{project}{env}{region}kv` (no hyphens) |
| ACR | Common | `astradeveastusacr` | `{project}{env}{region}acr` (no hyphens) |
| Log Analytics | Common | `astra-dev-eastus-law` | `{project}-{env}-{region}-law` |
| CAE Subnet | Tenant | `snet-nbrly-dev-cae` | `snet-{tenant}-{env}-cae` |
| Container App Env | Tenant | `nbrly-dev-cae` | `{tenant}-{env}-cae` |
| Managed Identity | Tenant | `nbrly-dev-uami` | `{tenant}-{env}-uami` |
| PostgreSQL | Tenant | `nbrly-dev-psql` | `{tenant}-{env}-psql` |
| Container App | Tenant | `nbrly-dev-app1-ca` | `{tenant}-{env}-{appName}-ca` |

### 5.3 Naming Rules

- **Lowercase**: Always use lowercase letters
- **Hyphens**: Use hyphens to separate components (except where Azure restricts)
- **No hyphens**: Key Vault and ACR don't allow hyphens or underscores
- **Consistency**: Follow pattern strictly for predictability

---

## 6. Configuration System

### 6.1 Configuration Files

**Common Configuration**: `iac-cli/config/parameters-{env}.json`

```json
{
  "env": "dev",
  "region": "eastus",
  "project": "astra",
  "vnetAddressPrefix": "10.100.0.0/16",
  "appGatewaySubnetPrefix": "10.100.0.0/24",
  "bastionSubnetPrefix": "10.100.1.0/26",
  "postgresSubnetPrefix": "10.100.2.0/24",
  "customDomain": {
    "certDomainName": "astrapia.io",
    "certificate": "*.astrapia.io",
    "certificateName": "astrapiaio",
    "certificateFilePath": "../certs/astrapia-io-dev.pfx",
    "tenantDomains": {
      "nbrly": "nbrly-dev.astrapia.io",
      "bloom": "bloom-dev.astrapia.io"
    }
  }
}
```

**Tenant Configuration**: `iac-cli/config/{tenant}/parameters-{env}.json`

```json
{
  "tenantName": "nbrly",
  "caeSubnetPrefix": "10.100.10.0/24",
  "domainName": "nbrly-dev.astrapia.io"
}
```

### 6.2 State Tracking Files

**Generated Infrastructure State**: `iac-cli/config/.generated/generated-infra-{env}.json`
- **Purpose**: Complete deployment state (legacy format)
- **Structure**: Hierarchical JSON with all resource details
- **Updated By**: All deployment scripts

**Infrastructure Tracking**: `iac-cli/config/infra-{env}.json` (NEW)
- **Purpose**: Simplified resource tracking
- **Structure**: Flat JSON with resource names and IDs
- **Updated By**: All deployment scripts after each resource creation

**Structure of `infra-{env}.json`**:
```json
{
  "project": "astra",
  "environment": "dev",
  "resources": {
    "resourceGroup": {
      "name": "astra-dev-eastus-rg",
      "id": "/subscriptions/.../resourceGroups/astra-dev-eastus-rg"
    },
    "vnet": {
      "name": "astra-dev-eastus-vnet",
      "id": "/subscriptions/.../virtualNetworks/astra-dev-eastus-vnet"
    },
    "logAnalytics": {
      "name": "astra-dev-eastus-law",
      "id": "/subscriptions/.../workspaces/astra-dev-eastus-law"
    },
    "containerRegistry": {
      "name": "astradeveastusacr",
      "id": "/subscriptions/.../registries/astradeveastusacr"
    },
    "keyVault": {
      "name": "astradeveastuskv",
      "id": "/subscriptions/.../vaults/astradeveastuskv"
    },
    "publicIp": {
      "name": "astra-dev-eastus-pip",
      "id": "/subscriptions/.../publicIPAddresses/astra-dev-eastus-pip",
      "ipAddress": "20.xxx.xxx.xxx"
    },
    "applicationGateway": {
      "name": "astra-dev-eastus-agw",
      "id": "/subscriptions/.../applicationGateways/astra-dev-eastus-agw"
    },
    "tenants": {
      "nbrly": {
        "subnet": {
          "name": "snet-nbrly-dev-cae",
          "id": "/subscriptions/.../subnets/snet-nbrly-dev-cae"
        },
        "managedIdentity": {
          "name": "nbrly-dev-uami",
          "id": "/subscriptions/.../userAssignedIdentities/nbrly-dev-uami",
          "clientId": "..."
        },
        "postgresServer": {
          "name": "nbrly-dev-psql",
          "id": "/subscriptions/.../flexibleServers/nbrly-dev-psql"
        },
        "containerAppEnv": {
          "name": "nbrly-dev-cae",
          "id": "/subscriptions/.../managedEnvironments/nbrly-dev-cae"
        },
        "containerApp": {
          "name": "nbrly-dev-app1-ca",
          "id": "/subscriptions/.../containerApps/nbrly-dev-app1-ca",
          "fqdn": "nbrly-dev-app1-ca.internal.xxx.eastus.azurecontainerapps.io"
        }
      },
      "bloom": {
        // Same structure as nbrly
      }
    }
  }
}
```

### 6.3 Environment Support

**Supported Environments**:
- `dev`: Development environment
- `stage`: Staging environment
- `prod`: Production environment

**Environment Validation**: All scripts validate environment with regex `^(dev|stage|prod)$`

---

## 7. Deployment Scripts

### 7.1 Script Execution Flow

1. **Parameter Validation**: Check PROJECT and ENV parameters
2. **Configuration Loading**: Load `parameters-{env}.json` files
3. **Variable Inference**: Derive all resource names from project-env-region
4. **Variable Printing**: Display formatted table of inferred names
5. **Azure Login**: Authenticate using Service Principal or interactive login
6. **Resource Creation**: Create resources one by one
7. **Resource Tracking**: Update `infra-{env}.json` after each resource
8. **Success Logging**: Log completion messages

### 7.2 Deployment Workflow

**Full Deployment**:
```bash
cd iac-cli/scripts
./00-deploy-all.sh astra dev
```

This will:
1. Deploy common infrastructure (VNet, ACR, Key Vault, App Gateway)
2. Deploy NBRLY tenant (subnet, UAMI, PostgreSQL, CAE, Container App)
3. Configure NBRLY routing in Application Gateway
4. Deploy BLOOM tenant (subnet, UAMI, PostgreSQL, CAE, Container App)
5. Configure BLOOM routing in Application Gateway

**Partial Deployment** (Common only):
```bash
cd iac-cli/scripts
./01-deploy-common-infra.sh astra dev
```

**Partial Deployment** (Single tenant):
```bash
cd iac-cli/scripts
./02-deploy-tenant-infra.sh nbrly astra dev
```

### 7.3 Idempotency

All scripts are **idempotent**:
- Check if resource exists before creating
- Skip creation if already exists
- Safe to run multiple times

Example:
```bash
if ! az group show --name "$rgName" &>/dev/null; then
    log_info "Creating resource group: $rgName"
    az group create --name "$rgName" --location "$region"
else
    log_info "Resource group already exists: $rgName"
fi
```

### 7.4 Error Handling

- **Exit on Error**: All scripts use `set -e` to exit on first error
- **Validation**: Parameter validation before any Azure operations
- **Logging**: Detailed logging for debugging
- **Resource Cleanup**: Manual cleanup required if deployment fails mid-way

---

## 8. Security Model

### 8.1 Identity & Access Management

- **Service Principal Authentication**: Recommended for automation
- **User-Assigned Managed Identity**: Per tenant for ACR pull, Key Vault access
- **Role-Based Access Control (RBAC)**: Least privilege principle
  - UAMI has `AcrPull` role on ACR
  - Application Gateway has Key Vault access for certificate
- **No Long-Lived Secrets**: Managed identities eliminate credential management

### 8.2 Network Security

- **Internal-Only Container Apps**: No public ingress, only accessible through Application Gateway
- **VNet Integration**: All Container App Environments integrated into VNet subnets
- **NSG Rules**: (Not yet implemented) Network Security Groups for subnet traffic control
- **Application Gateway WAF**: Web Application Firewall in Prevention mode
- **Private Endpoints**: (Planned) For ACR and Key Vault

### 8.3 Secrets Management

- **Azure Key Vault**: Centralized secret storage
- **Wildcard SSL Certificate**: `*.astrapia.io` stored in Key Vault
- **Database Connection Strings**: Stored as Key Vault secrets
- **No Secrets in Code**: All secrets referenced by name only
- **Credential Files**: In `creds/` directory, excluded from git

### 8.4 Data Protection

- **SSL/TLS Termination**: At Application Gateway with re-encryption to backends
- **Encryption at Rest**: Default for PostgreSQL, Key Vault, ACR
- **Encryption in Transit**: HTTPS everywhere

### 8.5 Monitoring & Logging

- **Log Analytics Workspace**: Centralized logging
- **Application Insights**: Application performance monitoring (planned)
- **Diagnostic Settings**: Resource logs sent to Log Analytics
- **Alerts**: (Planned) High CPU, restart count, failed pulls

---

## 9. Recent Work & Changes

### 9.1 PROJECT Parameter Implementation (Latest)

**Date**: 2025-01-21  
**Purpose**: Add PROJECT parameter to all scripts for resource name inference

**Changes Made**:
1. ✅ Added PROJECT as required first parameter to all 7 deployment scripts
2. ✅ Implemented resource name inference from `{project}-{env}-{region}` pattern
3. ✅ Added pre-creation variable printing (formatted tables)
4. ✅ Created `infra-{ENV}.json` tracking file
5. ✅ Implemented post-creation resource tracking
6. ✅ Updated common resource scripts (01-deploy-common-infra.sh)
7. ✅ Updated tenant resource scripts (nbrly/01, bloom/01)
8. ✅ Updated routing scripts (nbrly/02, bloom/02)
9. ✅ Created comprehensive documentation (DEPLOYMENT_CHANGES.md)

**Modified Scripts**:
- `00-deploy-all.sh`: Added PROJECT parameter, passes to child scripts
- `01-deploy-common-infra.sh`: Accepts PROJECT, prints variables, tracks resources
- `02-deploy-tenant-infra.sh`: Accepts PROJECT as second parameter
- `nbrly/01-deploy-tenant-resources.sh`: Accepts PROJECT, prints tenant variables, tracks tenant resources
- `nbrly/02-configure-routing.sh`: Accepts PROJECT parameter
- `bloom/01-deploy-tenant-resources.sh`: Same as nbrly
- `bloom/02-configure-routing.sh`: Same as nbrly

**New Files Created**:
- `docs/DEPLOYMENT_CHANGES.md`: Full documentation of PROJECT parameter changes
- `iac-cli/config/infra-{env}.json`: Resource tracking files (created at runtime)

**Testing Results**:
- ✅ Parameter validation: Scripts reject missing PROJECT parameter correctly
- ✅ Variable printing: Formatted tables display all inferred resource names
- ✅ File creation: `infra-dev.json` created with proper JSON structure
- ✅ Resource tracking: Resources written to file after creation with name and ID
- ✅ Deployment execution: Successfully started deployment (stopped due to incomplete config)

**Benefits**:
- **Flexibility**: Same scripts work for any project name
- **Transparency**: See all resource names before any creation
- **Tracking**: Simple JSON file tracks created resources
- **Multi-Project**: Can deploy multiple projects in same subscription
- **Predictability**: Clear naming pattern visible before deployment

### 9.2 Multi-Environment Support (Previous Session)

**Date**: Prior to 2025-01-21  
**Purpose**: Support dev, stage, prod environments

**Changes Made**:
1. ✅ Added ENV parameter to all deployment scripts (defaults to dev)
2. ✅ Environment validation with regex `^(dev|stage|prod)$`
3. ✅ Created environment-specific config files
   - `parameters-stage.json`
   - `parameters-prod.json`
   - `{tenant}/parameters-stage.json`
   - `{tenant}/parameters-prod.json`
4. ✅ Environment-specific state files
   - `generated-infra-{env}.json`
   - `infra-{env}.json`
5. ✅ Variable naming conflict resolution (ENV vs env in scripts)

**Benefits**:
- **Isolation**: Separate infrastructure for dev/stage/prod
- **Promotion**: Test in dev, promote to stage, deploy to prod
- **Safety**: Environment validation prevents accidental deployments

### 9.3 Application Implementation

**Date**: Prior to current session  
**Purpose**: Create sample FastAPI applications for testing

**Created**:
- ✅ 4 FastAPI applications (2 per tenant)
  - NBRLY: `nbapp1` (Items API), `nbapp2` (Tasks API)
  - BLOOM: `bmapp1` (Products API), `bmapp2` (Users API)
- ✅ Dockerfiles for each application
- ✅ Build and push scripts for ACR
- ✅ Deployment scripts for Container Apps
- ✅ Application Gateway routing configuration scripts

**Features**:
- FastAPI with automatic OpenAPI docs
- Health check endpoints (startup, readiness, liveness)
- Root path configuration for Application Gateway routing
- CORS support
- Comprehensive error handling

**Location**: `app-gtway-apps-previous/` (previous implementation)

### 9.4 Infrastructure Design Evolution

**Initial Design**:
- Hardcoded resource names
- Single environment (dev)
- Manual parameter passing

**Current Design**:
- PROJECT-based resource naming
- Multi-environment support (dev/stage/prod)
- Configuration-driven deployment
- Resource tracking and state management
- Pre-creation variable visibility

---

## 10. Key Documentation References

### 10.1 Project Instructions (.github/instructions/)

| File | Purpose |
|------|---------|
| `project-description.instructions.md` | Core project requirements, multi-tenancy model, security standards |
| `azure-ca-appgtwy-detail-design.instructions.md` | Detailed infrastructure design, network architecture, resource naming |
| `directory-structure.instructions.md` | Directory layout rules, folder purposes |
| `iac-naming-convention.instructions.md` | Comprehensive naming conventions for all resources |
| `capacity-container-size-analysis.instructions.md` | Container sizing and capacity planning |
| `shell.instructions.md` | Shell scripting best practices |

### 10.2 Documentation (docs/)

| File | Purpose |
|------|---------|
| `DEPLOYMENT_CHANGES.md` | Recent PROJECT parameter implementation details |
| `deployment-guide.md` | Step-by-step deployment instructions |
| `ssl-certificate-setup.md` | SSL/TLS certificate configuration guide |
| `azure-ca-appgtwy-imp-plan.md` | Original implementation plan |
| `WORKSPACE_CONTEXT.md` | This comprehensive context document |

### 10.3 Implementation Summaries

| File | Purpose |
|------|---------|
| `IMPLEMENTATION_SUMMARY.md` | FastAPI application implementation details |
| `ISOLATION_IMPLEMENTATION_REPORT.md` | Tenant isolation implementation |
| `QUICK_START_GUIDE.md` | Quick start for new developers |
| `TODO.md` | Task tracking for infrastructure phases |

### 10.4 Configuration Examples

**Common Config**: `iac-cli/config/parameters-dev.json`
```json
{
  "env": "dev",
  "region": "eastus",
  "project": "astra",
  "vnetAddressPrefix": "10.100.0.0/16",
  "appGatewaySubnetPrefix": "10.100.0.0/24",
  "bastionSubnetPrefix": "10.100.1.0/26",
  "postgresSubnetPrefix": "10.100.2.0/24",
  "customDomain": {
    "certDomainName": "astrapia.io",
    "certificate": "*.astrapia.io",
    "certificateName": "astrapiaio",
    "certificateFilePath": "../certs/astrapia-io-dev.pfx",
    "tenantDomains": {
      "nbrly": "nbrly-dev.astrapia.io",
      "bloom": "bloom-dev.astrapia.io"
    }
  }
}
```

**Tenant Config**: `iac-cli/config/nbrly/parameters-dev.json`
```json
{
  "tenantName": "nbrly",
  "caeSubnetPrefix": "10.100.10.0/24",
  "domainName": "nbrly-dev.astrapia.io"
}
```

### 10.5 Azure Documentation References

Key Azure resources used in this project:
- [Azure Container Apps Overview](https://learn.microsoft.com/en-us/azure/container-apps/overview)
- [VNet Integration for Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom?tabs=bash&pivots=azure-cli)
- [Application Gateway with Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway?tabs=default-domain)
- [User-Defined Routes](https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes)
- [Rule-Based Routing with Custom Domains](https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing-custom-domain)

---

## 11. Continuation Guidelines

### 11.1 For Future Prompts

When resuming work on this project:

1. **Read this document first** to understand the full context
2. **Check `docs/DEPLOYMENT_CHANGES.md`** for latest script changes
3. **Review `TODO.md`** for pending tasks
4. **Verify environment** before making changes (`dev`, `stage`, or `prod`)
5. **Follow naming conventions** strictly (section 5)
6. **Test in dev first** before promoting to stage/prod
7. **Update documentation** in `docs/` folder after significant changes

### 11.2 Common Tasks

**Add a new tenant**:
1. Create `iac-cli/config/{tenant}/parameters-{env}.json` for each environment
2. Copy `nbrly` or `bloom` scripts folder, rename to new tenant
3. Update `00-deploy-all.sh` to include new tenant deployment
4. Update VNet design to include new tenant subnet
5. Deploy: `./02-deploy-tenant-infra.sh {tenant} astra dev`

**Deploy to new environment**:
1. Create `parameters-stage.json` or `parameters-prod.json` if not exists
2. Create tenant-specific config files for new environment
3. Update DNS zone configuration
4. Run deployment: `./00-deploy-all.sh astra stage` or `./00-deploy-all.sh astra prod`

**Add new container app to existing tenant**:
1. Update tenant deployment script to create additional container app
2. Update routing script to add path-based routing rules
3. Build and push app image to ACR
4. Deploy: `./02-deploy-tenant-infra.sh {tenant} astra dev`

**Troubleshoot deployment**:
1. Check script output for errors
2. Review `infra-{env}.json` to see what was created
3. Check Azure Portal for resource state
4. Review logs in `iac-cli/logs/` directory
5. Verify authentication: `./helpers/azure-login.sh`

### 11.3 Best Practices

- **Always use PROJECT parameter**: Never hardcode project names
- **Print before create**: Always show inferred variables before deployment
- **Track resources**: Update `infra-{env}.json` after each resource creation
- **Document changes**: Update `docs/` folder for significant changes
- **Test idempotency**: Run scripts multiple times to ensure they handle existing resources
- **Version control**: Commit after each logical change
- **Secure credentials**: Never commit files in `creds/` directory

### 11.4 Known Limitations

- **NSG Rules**: Not yet implemented (planned)
- **Private Endpoints**: Not yet implemented for ACR and Key Vault (planned)
- **Application Insights**: Integration planned but not implemented
- **Alerts**: Monitoring alerts not yet configured
- **DNS Automation**: DNS record creation is manual (could be automated)
- **Certificate Renewal**: Manual process (could be automated with Key Vault integration)
- **Resource Cleanup**: No automated cleanup scripts (manual deletion required)

### 11.5 Next Steps (Potential)

**Infrastructure Enhancements**:
- [ ] Implement NSG rules for subnet traffic control
- [ ] Add private endpoints for ACR and Key Vault
- [ ] Configure Application Insights for container apps
- [ ] Set up monitoring alerts (CPU, memory, restarts)
- [ ] Automate DNS record creation/updates
- [ ] Add Azure Bastion for secure VM access

**Security Improvements**:
- [ ] Implement Azure Policy for governance
- [ ] Enable Defender for Cloud
- [ ] Configure Azure Firewall for egress traffic
- [ ] Implement runtime security scanning
- [ ] Add secret rotation automation
- [ ] Configure JIT VM access

**Operational Excellence**:
- [ ] Create resource cleanup scripts
- [ ] Add deployment rollback capability
- [ ] Implement blue-green deployment
- [ ] Add automated testing for infrastructure
- [ ] Create CI/CD pipeline for infrastructure deployment
- [ ] Add cost tracking and budgets

**Documentation**:
- [ ] Create architecture diagrams
- [ ] Document disaster recovery procedures
- [ ] Create runbook for common operations
- [ ] Add troubleshooting guide
- [ ] Document security incident response

---

## 12. Session Summary

### 12.1 Work Completed in This Session

**Objective**: Create comprehensive workspace context document

**Tasks Completed**:
1. ✅ Scanned entire workspace structure
2. ✅ Reviewed all instruction files
3. ✅ Analyzed recent deployment changes
4. ✅ Documented complete architecture and design
5. ✅ Captured all naming conventions
6. ✅ Documented configuration system
7. ✅ Explained deployment scripts in detail
8. ✅ Outlined security model
9. ✅ Summarized recent work (PROJECT parameter implementation)
10. ✅ Compiled key documentation references
11. ✅ Created continuation guidelines
12. ✅ Documented next steps and known limitations

**Document Created**: `docs/WORKSPACE_CONTEXT.md` (this file)

### 12.2 Key Insights from Analysis

1. **Well-Structured Project**: Clear separation of concerns between common and tenant infrastructure
2. **Security-Focused**: Multiple layers of security (managed identities, Key Vault, private networking)
3. **Production-Ready Pattern**: Multi-environment support, idempotent scripts, resource tracking
4. **Comprehensive Documentation**: Extensive instruction files and implementation guides
5. **Scalable Design**: VNet designed for 5 tenants, easily extensible
6. **Modern IaC Practices**: Configuration-driven, parameter validation, state tracking

### 12.3 Project Health

**Strengths**:
- ✅ Clear architecture and design
- ✅ Comprehensive documentation
- ✅ Multi-environment support
- ✅ Security best practices
- ✅ Idempotent deployment scripts
- ✅ Resource tracking and state management

**Areas for Improvement**:
- ⚠️ NSG rules not yet implemented
- ⚠️ Private endpoints planned but not configured
- ⚠️ Monitoring and alerting incomplete
- ⚠️ DNS automation manual
- ⚠️ No automated cleanup/rollback

**Overall Assessment**: The project is well-designed and follows Azure best practices. The infrastructure code is production-ready with proper multi-environment support, security controls, and comprehensive documentation.

---

## 13. Quick Reference

### 13.1 Essential Commands

**Deploy full infrastructure (dev)**:
```bash
cd iac-cli/scripts
./00-deploy-all.sh astra dev
```

**Deploy only common infrastructure**:
```bash
cd iac-cli/scripts
./01-deploy-common-infra.sh astra dev
```

**Deploy single tenant**:
```bash
cd iac-cli/scripts
./02-deploy-tenant-infra.sh nbrly astra dev
```

**Test Azure login**:
```bash
cd iac-cli/scripts
source helpers/azure-login.sh
azure_login
```

**View created resources**:
```bash
cat iac-cli/config/infra-dev.json | jq .
```

### 13.2 Important File Locations

| File/Directory | Purpose | Location |
|----------------|---------|----------|
| Deployment scripts | Infrastructure deployment | `iac-cli/scripts/` |
| Common config | Shared parameters | `iac-cli/config/parameters-{env}.json` |
| Tenant config | Tenant-specific params | `iac-cli/config/{tenant}/parameters-{env}.json` |
| Resource tracking | Created resources | `iac-cli/config/infra-{env}.json` |
| Credentials | Service principal creds | `iac-cli/creds/azure-credentials-{env}.cred` |
| Documentation | All docs | `docs/` |
| Instructions | Project guidelines | `.github/instructions/` |

### 13.3 Resource Name Quick Reference

**Common Resources** (project: astra, env: dev, region: eastus):
- Resource Group: `astra-dev-eastus-rg`
- VNet: `astra-dev-eastus-vnet`
- App Gateway: `astra-dev-eastus-agw`
- Public IP: `astra-dev-eastus-pip`
- Key Vault: `astradeveastuskv`
- ACR: `astradeveastusacr`
- Log Analytics: `astra-dev-eastus-law`

**Tenant Resources** (tenant: nbrly, env: dev):
- Subnet: `snet-nbrly-dev-cae`
- CAE: `nbrly-dev-cae`
- UAMI: `nbrly-dev-uami`
- PostgreSQL: `nbrly-dev-psql`
- Container App: `nbrly-dev-app1-ca`

---

**End of Workspace Context Document**

This document provides a complete reference for understanding and continuing work on the platform-nbrly project. It should be read before starting any new work and updated after significant changes.

For questions or clarifications, refer to:
- Project instructions in `.github/instructions/`
- Documentation in `docs/`
- Script comments in `iac-cli/scripts/`
