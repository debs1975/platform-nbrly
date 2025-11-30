# Astra Platform - Implemented Azure Architecture

## Overview
This document describes the actual implemented architecture for the Astra multi-tenant platform, as deployed and orchestrated by the scripts and configuration files in this repository. It reflects the current state of resources, networking, routing, identity, and automation.

---

## High-Level Architecture (Mermaid)

```mermaid
flowchart TD
  Internet --> PublicIP["Public IP (App Gateway)"]
  PublicIP --> AGW["Application Gateway\n(Routing, SSL, WAF, Managed Identity)"]
  AGW --> NbrlyCAE["Nbrly CAE Subnet\n(nbrly-dev-cae)"]
  AGW --> BloomCAE["Bloom CAE Subnet\n(bloom-dev-cae)"]
  NbrlyCAE --> Nbapp1["Nbrly App 1"]
  NbrlyCAE --> Nbapp2["Nbrly App 2"]
  BloomCAE --> Bmapp1["Bloom App 1"]
  BloomCAE --> Bmapp2["Bloom App 2"]
  AGW -.-> KeyVault["Key Vault\n(SSL, Secrets)"]
  AGW -.-> ACR["Container Registry"]
  NbrlyCAE -.-> PrivateDNS["Private DNS Zone"]
  BloomCAE -.-> PrivateDNS
  KeyVault -.-> AGW
  ACR -.-> Nbapp1
  ACR -.-> Nbapp2
  ACR -.-> Bmapp1
  ACR -.-> Bmapp2
```

---

## Detailed Azure Resource Map (Mermaid)

```mermaid
graph TD
  RG["Resource Group: astra-dev-eastus-rg"]
  RG --> VNet["VNet: astra-dev-eastus-vnet\n(10.100.0.0/16)"]
  VNet --> SubnetAGW["Subnet: appgw-subnet"]
  VNet --> SubnetNbrly["Subnet: nbrly-cae-subnet"]
  VNet --> SubnetBloom["Subnet: bloom-cae-subnet"]
  SubnetAGW --> AGW["Application Gateway\n(astar-dev-eastus-agw)"]
  AGW --> PublicIP["Public IP: astra-dev-eastus-pip"]
  AGW --> AGWMI["Managed Identity: agw-managed-identity"]
  AGW --> KeyVault["Key Vault: astradeveastuskv"]
  AGW --> Cert["SSL Certificate"]
  AGW --> Routing["Routing Rules"]
  SubnetNbrly --> NbrlyCAE["Nbrly CAE: nbrly-dev-cae\nStatic IP: 10.100.10.122"]
  NbrlyCAE --> Nbapp1["App: nbapp1"]
  NbrlyCAE --> Nbapp2["App: nbapp2"]
  SubnetBloom --> BloomCAE["Bloom CAE: bloom-dev-cae\nStatic IP: 10.100.11.184"]
  BloomCAE --> Bmapp1["App: bmapp1"]
  BloomCAE --> Bmapp2["App: bmapp2"]
  RG --> ACR["Container Registry: astradeveastusacr"]
  RG --> PrivateDNS["Private DNS Zones"]
  PrivateDNS --> VNet
  RG --> MI_Nbrly["Managed Identity: nbrly-dev-uami"]
  RG --> MI_Bloom["Managed Identity: bloom-dev-uami"]
```

---

## Resource Inventory

### Resource Group
- **Name:** astra-dev-eastus-rg
- **Location:** eastus
- **Subscription:** 984059e7-2907-4273-8569-703dddc5adfa

### Networking
- **Virtual Network:** astra-dev-eastus-vnet (10.100.0.0/16)
  - **Subnets:**
    - appgw-subnet (Application Gateway)
    - nbrly-cae-subnet (Nbrly CAE)
    - bloom-cae-subnet (Bloom CAE)
    - Additional subnets for isolation and future expansion

### Application Gateway
- **Name:** astra-dev-eastus-agw
- **SKU:** Standard_v2
- **Subnet:** appgw-subnet
- **Public IP:** astra-dev-eastus-pip
- **Managed Identity:** agw-managed-identity
- **SSL Certificate:** Managed via Key Vault
- **Routing:**
  - Backend pools point to CAE static IPs
  - Health probes, HTTP settings, listeners, and routing rules per tenant

### Container App Environments (CAE)
- **Nbrly CAE:** nbrly-dev-cae
  - **Static IP:** 10.100.10.122
  - **Default Domain:** grayfield-aa4022a1.eastus.azurecontainerapps.io
  - **Apps:** nbapp1, nbapp2
- **Bloom CAE:** bloom-dev-cae
  - **Static IP:** 10.100.11.184
  - **Default Domain:** graycliff-28ad9dd7.eastus.azurecontainerapps.io
  - **Apps:** bmapp1, bmapp2

### Container Registry
- **Name:** astradeveastusacr
- **Scope:** Shared for all tenants

### Key Vault
- **Name:** astradeveastuskv
- **Purpose:** SSL certificates, secrets
- **Access:** Managed identities and RBAC

### Managed Identities
- **agw-managed-identity:** For Application Gateway
- **nbrly-dev-uami:** For Nbrly tenant
- **bloom-dev-uami:** For Bloom tenant

### Private DNS Zones
- **Purpose:** Custom domain resolution for CAE apps
- **VNet Links:** Created for each tenant subnet

---

## Networking & Isolation
- All resources are deployed in a single VNet for isolation.
- Subnets are delegated for Application Gateway and CAE environments.
- CAE apps are only accessible via Application Gateway (no public exposure).
- Private DNS zones ensure internal name resolution for CAE apps.

---

## Routing & Traffic Flow
- **Ingress:**
  - Internet → Public IP → Application Gateway
- **Routing:**
  - Application Gateway forwards traffic to CAE static IPs based on routing rules.
  - Health probes and HTTP settings ensure tenant isolation and health monitoring.
- **Egress:**
  - CAE apps respond via Application Gateway.

---

## Identity & Access Management
- Managed identities are used for secure access to Key Vault and other resources.
- RBAC assignments are automated via scripts.
- Each tenant has a dedicated managed identity for app deployment and access.

---

## Certificate & DNS Management
- SSL certificates are stored in Key Vault and referenced by Application Gateway.
- DNS zones are managed for custom domains and private resolution.
- VNet links connect DNS zones to tenant subnets.

---

## Automation & Script Orchestration
- **01-deploy-common-infra.sh:** Deploys shared resources (VNet, subnets, ACR, Key Vault, Application Gateway, managed identities).
- **02-deploy-tenant-infra.sh:** Wrapper for tenant-specific resource deployment.
- **03-deploy-tenant-resources.sh:** Creates CAE environments, private DNS zones, VNet links, and managed identities for each tenant.
- **04-configure-routing.sh:** Configures Application Gateway backend pools, health probes, HTTP settings, listeners, and routing rules for each tenant.
- **Configuration files:** All resource names, IDs, and properties are parameterized and tracked in infra-dev.json and parameters-dev.json.

---

## Security & Best Practices
- All secrets and certificates are stored in Key Vault.
- No direct public access to CAE apps; all ingress is via Application Gateway.
- RBAC and managed identities are used for least-privilege access.
- Private DNS and VNet links ensure secure internal resolution.

---

## Diagram (Textual)


---

## Complete Traffic Flow (Mermaid)
---

## Block Flow Diagram (Mermaid)

```mermaid
flowchart LR
  RG["Resource Group"]
  VNet["Virtual Network"]
  SubnetAGW["App Gateway Subnet"]
  SubnetNbrly["Nbrly CAE Subnet"]
  SubnetBloom["Bloom CAE Subnet"]
  AGW["Application Gateway"]
  PIP["Public IP"]
  KeyVault["Key Vault"]
  ACR["Container Registry"]
  MI_AGW["Managed Identity (AGW)"]
  MI_Nbrly["Managed Identity (Nbrly)"]
  MI_Bloom["Managed Identity (Bloom)"]
  NbrlyCAE["Nbrly CAE"]
  BloomCAE["Bloom CAE"]
  Nbapp1["Nbrly App1"]
  Nbapp2["Nbrly App2"]
  Bmapp1["Bloom App1"]
  Bmapp2["Bloom App2"]
  DNS["Private DNS Zones"]

  RG --> VNet
  VNet --> SubnetAGW
  VNet --> SubnetNbrly
  VNet --> SubnetBloom
  SubnetAGW --> AGW
  AGW --> PIP
  AGW --> KeyVault
  AGW --> MI_AGW
  AGW --> NbrlyCAE
  AGW --> BloomCAE
  RG --> ACR
  RG --> MI_Nbrly
  RG --> MI_Bloom
  SubnetNbrly --> NbrlyCAE
  SubnetBloom --> BloomCAE
  NbrlyCAE --> Nbapp1
  NbrlyCAE --> Nbapp2
  BloomCAE --> Bmapp1
  BloomCAE --> Bmapp2
  RG --> DNS
  DNS --> VNet
```

```mermaid
sequenceDiagram
    participant User as Internet User
    participant DNS as DNS Resolver
    participant AGW as Application Gateway
    participant Cert as Key Vault (SSL)
    participant NbrlyCAE as Nbrly CAE
    participant BloomCAE as Bloom CAE
    participant Nbapp1 as Nbrly App1
    participant Nbapp2 as Nbrly App2
    participant Bmapp1 as Bloom App1
    participant Bmapp2 as Bloom App2

    User->>DNS: Resolve app domain (e.g. nbapp1.astrapia.io)
    DNS->>AGW: Returns Public IP of Application Gateway
    User->>AGW: HTTPS Request (SNI: nbapp1.astrapia.io)
    AGW->>Cert: Validate SSL certificate (from Key Vault)
    AGW->>NbrlyCAE: Forward request to CAE static IP (routing rule)
    NbrlyCAE->>Nbapp1: Route to nbapp1 container app
    Nbapp1-->>NbrlyCAE: App response
    NbrlyCAE-->>AGW: Return response
    AGW-->>User: HTTPS response

    AGW->>NbrlyCAE: Health probe (periodic)
    AGW->>BloomCAE: Health probe (periodic)
    AGW->>Nbapp2: Route to nbapp2 if rule matches
    AGW->>Bmapp1: Route to bmapp1 if rule matches
    AGW->>Bmapp2: Route to bmapp2 if rule matches
```

---

## Change Management
- All changes are tracked in configuration files and deployment logs.
- Backups are created before each deployment.
- Scripts are idempotent and safe for repeated execution.

---

## References
- See `README.md`, `DEPLOYMENT_CHANGES.md`, and script comments for further details.
- For technical design, see `app-gateway-apps-technical-design.md` and `azure-ca-appgtwy-imp-plan.md`.
