# Azure Infrastructure Design - Development Environment

**Project**: platform-nbrly  
**Environment**: Development (dev)  
**Region**: eastus  
**Generated**: November 9, 2025

---

## Executive Summary

This document outlines the secure Azure infrastructure architecture for deploying the nbrly full-stack application (React + FastAPI + PostgreSQL) in the development environment using Azure Container Apps with VNet integration, managed identities, and private networking.

### Design Decisions

- **Container Apps for unified orchestration**: Both frontend (React) and backend (FastAPI) deployed on Azure Container Apps sharing a common environment for consistent management and monitoring
- **Security-first approach**: All components VNet-integrated with private endpoints, managed identity authentication, and Key Vault for secrets (zero hardcoded credentials)
- **Development-optimized SKUs**: Using Basic/Burstable tier resources to minimize costs while maintaining production-like architecture
- **Layered deployment model**: Infrastructure deployed in 5 sequential layers (networking → security → compute → data → monitoring) for safe, repeatable provisioning
- **Crossplane-ready naming**: Consistent `{{project}}-{{env}}-{{region}}-{{resource}}` pattern with lowercase variables to facilitate future IaC migration
- **PostgreSQL with private connectivity**: Azure Database for PostgreSQL Flexible Server accessible only via private endpoint within VNet

---

## Architecture Overview

```mermaid
graph TB
    subgraph "Azure Subscription"
        RG[Resource Group<br/>nbrly-dev-eastus-rg]
        
        subgraph "Networking Layer"
            VNet[Virtual Network<br/>nbrly-dev-eastus-vnet<br/>10.0.0.0/22]
            SubnetCAE[Container Apps Subnet<br/>nbrly-dev-eastus-subnet-cae<br/>10.0.0.0/23]
            SubnetPE[Private Endpoint Subnet<br/>nbrly-dev-eastus-subnet-pe<br/>10.0.2.0/26]
            NSG[Network Security Group<br/>nbrly-dev-eastus-nsg]
            PrivateDNS[Private DNS Zones]
        end
        
        subgraph "Security Layer"
            KV[Key Vault<br/>nbrlydeveastuskv]
            UAMI[User-Assigned Identity<br/>nbrly-dev-eastus-uami]
        end
        
        subgraph "Compute Layer"
            ACR[Container Registry<br/>nbrlydeveastusacr<br/>Basic SKU]
            CAE[Container Apps Environment<br/>nbrly-dev-eastus-cae]
            FrontendCA[Frontend Container App<br/>nbrly-dev-eastus-frontend-ca]
            BackendCA[Backend Container App<br/>nbrly-dev-eastus-backend-ca]
        end
        
        subgraph "Data Layer"
            PSQL[PostgreSQL Flexible Server<br/>nbrly-dev-eastus-psql<br/>Burstable B1ms]
            PEPostgres[Private Endpoint<br/>PostgreSQL]
        end
        
        subgraph "Monitoring Layer"
            LAW[Log Analytics Workspace<br/>nbrly-dev-eastus-law]
            AppInsights[Application Insights<br/>nbrly-dev-eastus-ai]
        end
    end
    
    VNet --> SubnetCAE
    VNet --> SubnetPE
    SubnetCAE --> CAE
    SubnetPE --> PEPostgres
    PEPostgres --> PSQL
    
    ACR --> FrontendCA
    ACR --> BackendCA
    CAE --> FrontendCA
    CAE --> BackendCA
    
    UAMI --> ACR
    UAMI --> KV
    UAMI --> PSQL
    FrontendCA --> UAMI
    BackendCA --> UAMI
    
    KV -.secrets.-> FrontendCA
    KV -.secrets.-> BackendCA
    BackendCA --> PEPostgres
    
    LAW --> AppInsights
    AppInsights --> FrontendCA
    AppInsights --> BackendCA
    
    NSG --> SubnetCAE
    PrivateDNS --> PEPostgres
    
    RG --> VNet
    RG --> KV
    RG --> UAMI
    RG --> ACR
    RG --> CAE
    RG --> PSQL
    RG --> LAW

    classDef networkClass fill:#e1f5ff,stroke:#0078d4,stroke-width:2px
    classDef securityClass fill:#fff4ce,stroke:#ffb900,stroke-width:2px
    classDef computeClass fill:#e5f3e5,stroke:#107c10,stroke-width:2px
    classDef dataClass fill:#ffe5e5,stroke:#d13438,stroke-width:2px
    classDef monitorClass fill:#f3e5ff,stroke:#8764b8,stroke-width:2px
    
    class VNet,SubnetCAE,SubnetPE,NSG,PrivateDNS networkClass
    class KV,UAMI securityClass
    class ACR,CAE,FrontendCA,BackendCA computeClass
    class PSQL,PEPostgres dataClass
    class LAW,AppInsights monitorClass
```

---

## Component Inventory

### Resource Group
| Resource | Name | Purpose |
|----------|------|---------|
| Resource Group | `nbrly-dev-eastus-rg` | Logical container for all dev environment resources |

### Networking Layer
| Resource | Name | CIDR/Config | Purpose |
|----------|------|-------------|---------|
| Virtual Network | `nbrly-dev-eastus-vnet` | 10.0.0.0/22 (1,024 IPs) | Network isolation boundary |
| Subnet (Container Apps) | `nbrly-dev-eastus-subnet-cae` | 10.0.0.0/23 (512 IPs) | Container Apps Environment integration (supports 200 apps) |
| Subnet (Private Endpoints) | `nbrly-dev-eastus-subnet-pe` | 10.0.2.0/26 (64 IPs) | Private endpoint connections (supports 30 endpoints) |
| Network Security Group | `nbrly-dev-eastus-nsg` | Applied to CAE subnet | Least-privilege ingress/egress rules |
| Private DNS Zone (PostgreSQL) | `privatelink.postgres.database.azure.com` | N/A | DNS resolution for private endpoints |

**CIDR Allocation Strategy**:
- **Total VNet**: 10.0.0.0/22 (1,024 IPs) - optimized for workload requirements
- **Container Apps Subnet**: 10.0.0.0/23 (512 IPs) - accommodates up to 200 Container Apps with auto-scaling replicas
- **Private Endpoints Subnet**: 10.0.2.0/26 (64 IPs) - supports up to 30 private endpoints with headroom
- **Reserved for Future Expansion**: 10.0.2.64/26 through 10.0.3.255/24 available for expansion

**Capacity Planning Details**:

*Container Apps Subnet Calculation*:
- Maximum Container Apps: 200
- Average replicas per app: 2.5 (accounting for auto-scaling)
- IP consumption: 200 apps × 2.5 replicas = 500 IPs
- Azure reserved IPs: 5 (.0, .1, .2, .3, .255)
- Subnet size: /23 (512 IPs) provides 507 usable IPs
- Headroom: 7 IPs (1.4% buffer) sufficient for dev environment burst scaling

*Private Endpoints Subnet Calculation*:
- Current private endpoints: 1 (PostgreSQL)
- Maximum private endpoints: 30
- IP consumption: 30 endpoints × 1 IP = 30 IPs
- Azure reserved IPs: 5
- Subnet size: /26 (64 IPs) provides 59 usable IPs
- Headroom: 24 IPs (80% buffer) allows for future services:
  - Storage Account private endpoint
  - Key Vault private endpoint
  - ACR private endpoint (if transitioning to Premium SKU)
  - Additional databases or services (Redis, Service Bus, etc.)

*VNet Efficiency*:
- Total allocated: 576 IPs (512 + 64)
- Total VNet capacity: 1,024 IPs
- Utilization: 56% (healthy for growth)
- Available for future subnets: 448 IPs
  - Could add /25 (128 IPs) for Application Gateway
  - Could add /26 (64 IPs) for Azure Bastion
  - Could add /26 (64 IPs) for additional services

*Scaling Scenarios*:
- **Current load** (10 apps, 1-2 replicas each): ~20 IPs used (4% of Container Apps subnet)
- **Moderate load** (50 apps, 2-3 replicas each): ~125 IPs used (24% of Container Apps subnet)
- **High load** (100 apps, 3-4 replicas each): ~350 IPs used (68% of Container Apps subnet)
- **Maximum capacity** (200 apps, 2-3 replicas each): ~500 IPs used (98% of Container Apps subnet)
- **Burst scenario** (100 apps scaling to 5 replicas): ~500 IPs used - still fits within /23 subnet

### Security Layer
| Resource | Name | SKU | Purpose |
|----------|------|-----|---------|
| Key Vault | `nbrlydeveastuskv` | Standard | Centralized secrets, certificates, keys storage |
| User-Assigned Managed Identity | `nbrly-dev-eastus-uami` | N/A | Service-to-service authentication |

**RBAC Assignments for UAMI**:
- `AcrPull` role on `nbrlydeveastusacr`
- `Key Vault Secrets User` role on `nbrlydeveastuskv`
- (Optional) Database authentication on PostgreSQL

### Compute Layer
| Resource | Name | SKU/Config | Purpose |
|----------|------|------------|---------|
| Container Registry | `nbrlydeveastusacr` | Basic | Private Docker image repository |
| Container Apps Environment | `nbrly-dev-eastus-cae` | Consumption | Shared runtime for frontend/backend |
| Frontend Container App | `nbrly-dev-eastus-frontend-ca` | 0.5 CPU / 1 GB RAM, 0-3 replicas | React SPA hosting (nginx) |
| Backend Container App | `nbrly-dev-eastus-backend-ca` | 0.5 CPU / 1 GB RAM, 0-5 replicas | FastAPI REST API |

### Data Layer
| Resource | Name | SKU | Storage | Purpose |
|----------|------|-----|---------|---------|
| PostgreSQL Flexible Server | `nbrly-dev-eastus-psql` | Burstable B1ms | 32 GB | Application database |
| Private Endpoint | `nbrly-dev-eastus-psql-pe` | N/A | N/A | Private connectivity to PostgreSQL |

**Database Configuration**:
- Backup retention: 7 days
- Zone redundancy: Disabled (dev)
- SSL enforcement: Required (TLS 1.2+)
- Public network access: Disabled
- Authentication: PostgreSQL native + optional Entra ID

### Monitoring Layer
| Resource | Name | Retention | Purpose |
|----------|------|-----------|---------|
| Log Analytics Workspace | `nbrly-dev-eastus-law` | 30 days | Centralized log aggregation |
| Application Insights | `nbrly-dev-eastus-ai` | 90 days | Application performance monitoring |

---

## Capacity Planning & Sizing Strategy

### Overview
This section details the capacity planning decisions for the development environment, optimized for up to 200 Container Apps and 30 private endpoints while minimizing costs.

### Network Capacity Details

**Current Allocation vs Maximum Capacity**:

| Component | Current Usage | Maximum Capacity | Utilization | Buffer |
|-----------|--------------|------------------|-------------|--------|
| Container Apps | 2 apps (frontend + backend) | 200 apps | 1% | 99% |
| Container App IPs | ~5 IPs (2-3 replicas) | 507 usable IPs | 1% | 99% |
| Private Endpoints | 1 (PostgreSQL) | 59 usable endpoints | 2% | 98% |
| Total VNet IPs | ~10 IPs | 1,019 usable IPs | 1% | 99% |

**IP Consumption Growth Projection**:
- **Month 1**: 10 IPs (2 apps, testing phase)
- **Month 3**: 50 IPs (20 apps, feature development)
- **Month 6**: 150 IPs (60 apps, pre-production testing)
- **Month 12**: 350 IPs (100-150 apps, full development)

### Compute Capacity Details

**Container Apps Resource Allocation**:

| App | Current Config | Peak Load Config | Monthly Cost (Current) | Monthly Cost (Peak) |
|-----|---------------|------------------|------------------------|---------------------|
| Frontend | 0.5 CPU, 1 GB, 0-3 replicas | 0.5 CPU, 1 GB, 0-5 replicas | ~$15 | ~$25 |
| Backend | 0.5 CPU, 1 GB, 0-5 replicas | 1.0 CPU, 2 GB, 0-10 replicas | ~$15 | ~$80 |

**Auto-Scaling Configuration**:
- **Frontend Scaling Rules**:
  - HTTP requests: Scale at 100 concurrent requests per replica
  - Min replicas: 0 (scale to zero during off-hours)
  - Max replicas: 3 (dev), 5 (peak testing)
  - Cool-down: 5 minutes
  
- **Backend Scaling Rules**:
  - HTTP requests: Scale at 50 concurrent requests per replica
  - CPU: Scale at 70% utilization
  - Min replicas: 0 (scale to zero during off-hours)
  - Max replicas: 5 (dev), 10 (peak load testing)
  - Cool-down: 5 minutes

**Container Apps Environment Capacity**:
- Shared environment supports unlimited Container Apps (within subnet IP constraints)
- Current: 2 apps consuming minimal environment resources
- Maximum: 200 apps supported by network configuration
- Environment-level metrics aggregated in Log Analytics

### Database Capacity Details

**PostgreSQL Flexible Server B1ms Specifications**:
- **Compute**: 1 vCore, 2 GiB RAM
- **Storage**: 32 GB SSD (expandable to 16 TB)
- **IOPS**: 640 baseline, burstable to 3,500
- **Max Connections**: ~100 concurrent (calculated: (RAM_GB * 1024 / 9.5))
- **Backup**: 7-day retention, no geo-redundancy
- **High Availability**: Disabled (single instance)

**Database Growth Projections**:
```
Current:     0.1 GB (empty database)
Month 1:     1 GB (initial development)
Month 3:     3 GB (feature data)
Month 6:     8 GB (integration testing data)
Month 12:    15 GB (comprehensive test datasets)
Year 2:      25 GB (historical test data)
```

**When to Upgrade Database**:
- Storage >25 GB → Expand storage to 64 GB (no downtime)
- Connections >80 → Upgrade to B2s (2 vCores, 4 GB RAM, ~200 connections)
- CPU >75% sustained → Upgrade to General Purpose D2ds_v4
- IOPS throttling → Move to General Purpose SKU with higher baseline IOPS

**Connection Pool Sizing**:
- Backend Container Apps: 10 connections per replica
- Max backend replicas: 5
- Total backend connections needed: 50
- Headroom: 50 connections (50% buffer)
- B1ms max connections (100): Adequate for development

### Storage Capacity Details

**Azure Container Registry (Basic SKU)**:
- **Storage Quota**: 10 GB
- **Current Usage**: <1 GB (2 images with few tags)
- **Projected Usage**:
  - Month 3: 2 GB (10 images, 3 tags each)
  - Month 6: 4 GB (20 images, 5 tags each)
  - Month 12: 8 GB (40 images, multiple tags)
- **Upgrade Trigger**: >8 GB storage usage → Upgrade to Standard (100 GB)

**Key Vault (Standard SKU)**:
- **Secrets**: Currently 3 (postgres-connection-string, api-secret-key, frontend-api-url)
- **Operations**: <1,000 per month (development usage)
- **Cost**: Negligible (~$0.50/month)
- **Capacity**: Virtually unlimited for dev workloads

### Monitoring & Logging Capacity Details

**Log Analytics Workspace Projections**:
| Month | Daily Ingestion | Storage (30-day retention) | Monthly Cost | Data Sources |
|-------|-----------------|----------------------------|--------------|--------------|
| 1 | 0.1 GB/day | 3 GB | Free (5 GB included) | 2 Container Apps, PostgreSQL |
| 3 | 0.5 GB/day | 15 GB | ~$6 | 10-20 Container Apps, ACR, PostgreSQL |
| 6 | 1.0 GB/day | 30 GB | ~$12 | 40-60 Container Apps, increased logging |
| 12 | 2.0 GB/day | 60 GB | ~$24 | 100+ Container Apps, full diagnostics |

**Application Insights Sizing**:
- **Current**: <0.5 GB/month (2 apps, development traffic)
- **Month 6**: 2-3 GB/month (20+ apps, integration testing)
- **Month 12**: 5-8 GB/month (60+ apps, comprehensive telemetry)
- **Sampling**: Not needed in dev (keep 100% for debugging)

**Log Retention Optimization**:
- **Real-time logs**: 30 days in Log Analytics (hot tier)
- **Historical logs**: Export to Storage Account after 30 days
- **Compliance logs**: Archive to Cool storage (long-term retention at 80% cost reduction)

### Cost Projection Summary

**Current Monthly Cost** (2 Container Apps, minimal usage):
| Resource | Current Cost | Optimized Cost (Scale-to-Zero) |
|----------|--------------|-------------------------------|
| Container Apps | $30 | $15 (50% reduction with scale-to-zero) |
| ACR | $5 | $5 |
| PostgreSQL | $25 | $25 |
| Key Vault | $1 | $1 |
| Private Endpoint | $8 | $8 |
| Log Analytics | Free | Free (within 5 GB limit) |
| VNet/NSG | Free | Free |
| **Total** | **$69** | **$54** |

**Projected Monthly Cost at Scale**:
| Timeline | Apps | Est. Monthly Cost | Notes |
|----------|------|-------------------|-------|
| Month 1 | 2-5 | $54-75 | Initial development |
| Month 3 | 10-20 | $100-150 | Feature development phase |
| Month 6 | 40-60 | $250-400 | Integration testing, increased replicas |
| Month 12 | 100-150 | $600-900 | Full development environment |

**Cost Optimization Strategies**:
1. **Scale-to-Zero**: Configure all non-critical Container Apps to scale to 0 replicas during off-hours (6 PM - 8 AM, weekends)
   - Savings: 60% of Container Apps costs (~$150-300/month at scale)
2. **Log Retention**: Keep only 7-day hot retention, archive rest to Storage
   - Savings: 70% of Log Analytics costs (~$15-20/month at scale)
3. **Resource Tagging**: Tag resources with owner/team for chargeback and optimization tracking
4. **Auto-Shutdown**: Implement Azure Automation runbook to stop dev resources on weekends
   - Additional savings: 30% (~$50-100/month at scale)

### Scaling Roadmap

**Immediate (Month 1-3)**:
- ✅ Current configuration adequate
- Monitor: Log Analytics ingestion, ACR storage
- Action: None required

**Near-term (Month 3-6)**:
- 📊 Monitor: PostgreSQL connections, Container Apps subnet utilization
- 🔄 Potential Actions:
  - Expand PostgreSQL storage to 64 GB if >25 GB used
  - Implement log archival to Storage Account
  - Add Storage Account private endpoint to Private Endpoints subnet

**Mid-term (Month 6-12)**:
- 📊 Monitor: Container Apps IP consumption, database performance
- 🔄 Potential Actions:
  - Upgrade PostgreSQL to B2s if connections >80 or CPU >75%
  - Upgrade ACR to Standard if storage >8 GB
  - Review and optimize Log Analytics queries to reduce ingestion costs

**Long-term (Month 12+)**:
- 📊 Monitor: VNet subnet utilization, overall cost trends
- 🔄 Migration Considerations:
  - Evaluate separate VNet for production-like dev environment
  - Consider Azure DevTest Labs for cost-optimized development VMs
  - Assess Container Apps vs AKS based on complexity and control needs

### Monitoring & Alerting Thresholds

**Proactive Alerts Configured**:
| Metric | Threshold | Action | Priority |
|--------|-----------|--------|----------|
| Container Apps Subnet IPs | >400 used (80%) | Plan subnet expansion | Medium |
| Private Endpoints Subnet IPs | >47 used (80%) | Review endpoint necessity | Low |
| PostgreSQL Storage | >25 GB (78%) | Expand storage to 64 GB | Medium |
| PostgreSQL Connections | >80 (80%) | Upgrade to B2s SKU | High |
| PostgreSQL CPU | >75% sustained | Upgrade SKU or optimize queries | High |
| ACR Storage | >8 GB (80%) | Upgrade to Standard SKU | Medium |
| Log Analytics Ingestion | >4 GB/day | Review log levels, implement sampling | Medium |
| Container Apps Restarts | >5/hour | Investigate app stability | High |

---

## Security Controls Mapping

### Identity & Access Management
| Control | Implementation | Status |
|---------|----------------|--------|
| No hardcoded credentials | All secrets in Key Vault, referenced by Container Apps | ✅ |
| Managed identity for ACR pull | UAMI assigned to Container Apps with AcrPull role | ✅ |
| Managed identity for Key Vault | UAMI has Key Vault Secrets User role | ✅ |
| Least privilege RBAC | Role assignments scoped to specific resources | ✅ |
| Service principal not used | Managed identity used exclusively | ✅ |

### Network Security
| Control | Implementation | Status |
|---------|----------------|--------|
| VNet integration | Container Apps Environment in dedicated subnet | ✅ |
| Private endpoints | PostgreSQL accessible only via private endpoint | ✅ |
| NSG rules | Inbound limited to HTTPS (443), internal traffic allowed | ✅ |
| TLS enforcement | HTTPS-only ingress, PostgreSQL requires SSL/TLS | ✅ |
| Internal backend communication | Backend-to-database over private network | ✅ |
| Public access disabled | PostgreSQL public network access disabled | ✅ |

### Data Protection
| Control | Implementation | Status |
|---------|----------------|--------|
| Encryption at rest | PostgreSQL and ACR use Azure-managed encryption | ✅ |
| Encryption in transit | TLS 1.2+ enforced for all connections | ✅ |
| Backup encryption | PostgreSQL backups encrypted automatically | ✅ |
| Key Vault soft delete | 90-day retention for deleted secrets | ✅ |

### Monitoring & Compliance
| Control | Implementation | Status |
|---------|----------------|--------|
| Diagnostic logging | All services send logs to Log Analytics | ✅ |
| Application monitoring | Application Insights integrated | ✅ |
| Alert rules | Image pull failures, high restart counts | ✅ |
| Resource tagging | Environment, Project, Owner, CostCenter tags | ✅ |

---

## Deployment Plan

### Prerequisites
1. Azure subscription with Contributor access
2. Azure CLI installed (version 2.50+)
3. `jq` installed for JSON parsing (optional but recommended)
4. Resource provider registrations:
   ```bash
   az provider register --namespace Microsoft.App
   az provider register --namespace Microsoft.DBforPostgreSQL
   az provider register --namespace Microsoft.Network
   az provider register --namespace Microsoft.KeyVault
   az provider register --namespace Microsoft.ContainerRegistry
   ```

### Deployment Sequence

**Layer 1: Networking** (~5 minutes)
```bash
cd scripts
chmod +x 01-deploy-networking.sh
./01-deploy-networking.sh
```
Creates: Resource Group, VNet, Subnets, NSG, Private DNS Zone

**Layer 2: Security** (~3 minutes)
```bash
chmod +x 02-deploy-security.sh
./02-deploy-security.sh
```
Creates: Key Vault, User-Assigned Managed Identity, RBAC assignments

**Layer 3: Compute** (~10 minutes)
```bash
chmod +x 03-deploy-compute.sh
./03-deploy-compute.sh
```
Creates: ACR, Container Apps Environment, Container Apps (frontend/backend)

**Layer 4: Data** (~15 minutes)
```bash
chmod +x 04-deploy-data.sh
./04-deploy-data.sh
```
Creates: PostgreSQL Flexible Server, Private Endpoint, DNS integration

**Layer 5: Monitoring** (~5 minutes)
```bash
chmod +x 05-deploy-monitoring.sh
./05-deploy-monitoring.sh
```
Creates: Log Analytics Workspace, Application Insights, Alert Rules, Diagnostic Settings

**Total Deployment Time**: ~40 minutes

---

## Verification Plan

### 1. Networking Validation
```bash
# Verify VNet and subnets
az network vnet show --resource-group nbrly-dev-eastus-rg --name nbrly-dev-eastus-vnet

# Verify NSG rules
az network nsg show --resource-group nbrly-dev-eastus-rg --name nbrly-dev-eastus-nsg

# Expected: VNet exists with 2 subnets, NSG applied to Container Apps subnet
```

### 2. Security Validation
```bash
# Verify Key Vault and RBAC
az keyvault show --name nbrlydeveastuskv --resource-group nbrly-dev-eastus-rg

# Verify managed identity
az identity show --resource-group nbrly-dev-eastus-rg --name nbrly-dev-eastus-uami

# Expected: Key Vault accessible, UAMI has correct role assignments
```

### 3. Compute Validation
```bash
# Verify ACR
az acr show --name nbrlydeveastusacr --resource-group nbrly-dev-eastus-rg

# Verify Container Apps Environment
az containerapp env show --name nbrly-dev-eastus-cae --resource-group nbrly-dev-eastus-rg

# Verify Container Apps
az containerapp show --name nbrly-dev-eastus-frontend-ca --resource-group nbrly-dev-eastus-rg
az containerapp show --name nbrly-dev-eastus-backend-ca --resource-group nbrly-dev-eastus-rg

# Expected: ACR operational, Container Apps running with managed identity assigned
```

### 4. Data Validation
```bash
# Verify PostgreSQL server
az postgres flexible-server show --resource-group nbrly-dev-eastus-rg --name nbrly-dev-eastus-psql

# Verify private endpoint
az network private-endpoint show --resource-group nbrly-dev-eastus-rg --name nbrly-dev-eastus-psql-pe

# Test database connectivity (from within VNet)
psql "host=nbrly-dev-eastus-psql.postgres.database.azure.com port=5432 dbname=postgres user=dbadmin sslmode=require"

# Expected: PostgreSQL accessible only via private endpoint, public access disabled
```

### 5. Monitoring Validation
```bash
# Verify Log Analytics
az monitor log-analytics workspace show --resource-group nbrly-dev-eastus-rg --workspace-name nbrly-dev-eastus-law

# Verify Application Insights
az monitor app-insights component show --app nbrly-dev-eastus-ai --resource-group nbrly-dev-eastus-rg

# Query logs
az monitor log-analytics query --workspace nbrly-dev-eastus-law --analytics-query "ContainerAppConsoleLogs_CL | take 10"

# Expected: Logs flowing from Container Apps to Log Analytics
```

---

## Cost Estimation (Development Environment)

**Current Baseline Cost** (2 Container Apps, minimal usage):

| Service | SKU | Configuration | Estimated Monthly Cost (USD) |
|---------|-----|---------------|------------------------------|
| Container Apps (Frontend) | 0.5 vCPU, 1 GB RAM | ~720 hrs (with scale-to-zero) | $15 |
| Container Apps (Backend) | 0.5 vCPU, 1 GB RAM | ~720 hrs (with scale-to-zero) | $15 |
| Container Apps Environment | Consumption | Shared environment | Included |
| Container Registry | Basic | 10 GB storage quota | $5 |
| PostgreSQL Flexible Server | Burstable B1ms | 1 vCore, 2 GB RAM, 32 GB storage | $25 |
| Key Vault | Standard | <10k operations/month | $1 |
| VNet & Subnets | Standard | VNet with 2 subnets | Free |
| Private Endpoint | Standard | 1 endpoint (PostgreSQL) | $8 |
| Log Analytics Workspace | Pay-as-you-go | ~1 GB ingestion/day, 30-day retention | Free (within 5 GB/month) |
| Application Insights | Pay-as-you-go | ~1 GB telemetry/month | Included (first 5 GB) |
| Network Security Group | Standard | NSG rules | Free |
| Private DNS Zone | Standard | 1 zone | $0.50 |
| **Total Baseline** | | | **~$69/month** |
| **With Scale-to-Zero Optimization** | | Off-hours shutdown | **~$54/month** |

**Cost Growth Projections** (based on capacity planning):

| Timeline | Container Apps | Total Infrastructure | Notes |
|----------|----------------|---------------------|-------|
| **Month 1-3** | 5-20 apps | $75-150/month | Initial development phase |
| **Month 3-6** | 20-60 apps | $150-400/month | Feature development, increased testing |
| **Month 6-12** | 60-150 apps | $400-900/month | Full development environment |
| **Month 12+** | 150-200 apps | $900-1,500/month | Maximum capacity utilization |

**Cost Breakdown at Scale** (Month 12 projection, 150 apps):

| Service | Configuration | Estimated Monthly Cost (USD) |
|---------|---------------|------------------------------|
| Container Apps (150 apps × 2-3 replicas avg) | ~400 vCPU-hours total | $600-800 |
| PostgreSQL (upgraded) | B2s or D2ds_v4, 64 GB storage | $50-150 |
| Container Registry (upgraded) | Standard, 100 GB | $20 |
| Log Analytics | 2 GB/day ingestion | $24 |
| Application Insights | 5-8 GB/month | $25-40 |
| Other Services | Key Vault, Private Endpoints, VNet | $15 |
| **Total at Scale** | | **$734-1,049/month** |

**Cost Optimization Opportunities**:
- **Scale-to-Zero**: Save 50-60% on Container Apps costs during off-hours (~$300-400/month savings)
- **Log Retention**: Archive logs to Storage after 7 days (save 70% on Log Analytics ~$15-20/month)
- **Auto-Shutdown**: Weekend shutdown via Azure Automation (additional 25% savings ~$150-250/month)
- **Total Potential Savings**: $465-670/month (50-65% cost reduction)

**Optimized Monthly Cost at Scale**: $400-600/month (with all optimizations)

*Note: Costs are estimates based on East US region pricing and may vary based on actual usage, Azure pricing changes, and promotional credits. See [Capacity Planning & Sizing Strategy](#capacity-planning--sizing-strategy) section for detailed projections and growth planning.*

---

## Environment Variables & Secrets

### Key Vault Secrets (to be created manually or via script)
| Secret Name | Example Value | Purpose |
|-------------|---------------|---------|
| `postgres-connection-string` | `postgresql://dbadmin:***@nbrly-dev-eastus-psql.postgres.database.azure.com/nbrly?sslmode=require` | Database connection |
| `api-secret-key` | `<generated-uuid>` | FastAPI JWT signing key |
| `frontend-api-url` | `https://nbrly-dev-eastus-backend-ca.azurecontainerapps.io` | Backend API endpoint |

### Container Apps Environment Variables
**Frontend (`nbrly-dev-eastus-frontend-ca`)**:
- `REACT_APP_API_URL`: Reference to `frontend-api-url` secret
- `REACT_APP_ENV`: `development`

**Backend (`nbrly-dev-eastus-backend-ca`)**:
- `DATABASE_URL`: Reference to `postgres-connection-string` secret
- `SECRET_KEY`: Reference to `api-secret-key` secret
- `ENVIRONMENT`: `development`
- `ALLOWED_ORIGINS`: `https://nbrly-dev-eastus-frontend-ca.azurecontainerapps.io`

---

## Operational Runbook

### How to Deploy Initial Infrastructure
```bash
# 1. Clone repository and navigate to project root
cd /path/to/platform-nbrly

# 2. Review and update parameters (if needed)
vi config/parameters-dev.json

# 3. Deploy in sequence
cd scripts
./01-deploy-networking.sh
./02-deploy-security.sh
./03-deploy-compute.sh
./04-deploy-data.sh
./05-deploy-monitoring.sh

# 4. Verify deployment
./99-verify-deployment.sh
```

### How to Deploy Application Containers
```bash
# Build and push images to ACR
az acr login --name nbrlydeveastusacr

# Frontend
docker build -t nbrlydeveastusacr.azurecr.io/frontend:latest ./frontend
docker push nbrlydeveastusacr.azurecr.io/frontend:latest

# Backend
docker build -t nbrlydeveastusacr.azurecr.io/backend:latest ./backend
docker push nbrlydeveastusacr.azurecr.io/backend:latest

# Update Container Apps with new images
az containerapp update \
  --name nbrly-dev-eastus-frontend-ca \
  --resource-group nbrly-dev-eastus-rg \
  --image nbrlydeveastusacr.azurecr.io/frontend:latest

az containerapp update \
  --name nbrly-dev-eastus-backend-ca \
  --resource-group nbrly-dev-eastus-rg \
  --image nbrlydeveastusacr.azurecr.io/backend:latest
```

### How to Access Application Logs
```bash
# Stream live logs (frontend)
az containerapp logs show \
  --name nbrly-dev-eastus-frontend-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# Stream live logs (backend)
az containerapp logs show \
  --name nbrly-dev-eastus-backend-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# Query historical logs via Log Analytics
az monitor log-analytics query \
  --workspace nbrly-dev-eastus-law \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'nbrly-dev-eastus-backend-ca' | order by TimeGenerated desc | take 50"
```

### How to Troubleshoot Common Issues

**Issue: Container App fails to start**
```bash
# Check Container App status
az containerapp show --name nbrly-dev-eastus-backend-ca --resource-group nbrly-dev-eastus-rg --query "properties.provisioningState"

# Check recent revisions
az containerapp revision list --name nbrly-dev-eastus-backend-ca --resource-group nbrly-dev-eastus-rg

# View detailed logs
az containerapp logs show --name nbrly-dev-eastus-backend-ca --resource-group nbrly-dev-eastus-rg --tail 100
```

**Issue: Cannot pull image from ACR**
```bash
# Verify managed identity has AcrPull role
az role assignment list --assignee $(az identity show --resource-group nbrly-dev-eastus-rg --name nbrly-dev-eastus-uami --query principalId -o tsv)

# Check ACR login server
az acr show --name nbrlydeveastusacr --query loginServer -o tsv

# Verify image exists
az acr repository list --name nbrlydeveastusacr
```

**Issue: Database connection fails**
```bash
# Verify private endpoint DNS resolution (from Container App environment)
nslookup nbrly-dev-eastus-psql.postgres.database.azure.com

# Check PostgreSQL firewall rules (should be empty if using private endpoint)
az postgres flexible-server firewall-rule list --resource-group nbrly-dev-eastus-rg --name nbrly-dev-eastus-psql

# Test connectivity (from Container App exec session)
az containerapp exec --name nbrly-dev-eastus-backend-ca --resource-group nbrly-dev-eastus-rg
# Inside container:
curl -v telnet://nbrly-dev-eastus-psql.postgres.database.azure.com:5432
```

---

## Next Steps

1. **Deploy Infrastructure**: Execute layered deployment scripts in sequence
2. **Configure Secrets**: Populate Key Vault with required secrets (database credentials, API keys)
3. **Build & Push Images**: Create Docker images for frontend/backend and push to ACR
4. **Update Container Apps**: Deploy container images to Container Apps
5. **Configure Custom Domains** (optional): Add custom domains and SSL certificates to Container Apps
6. **Set Up CI/CD**: Create GitHub Actions or Azure DevOps pipelines for automated deployments
7. **Monitor & Optimize**: Review Application Insights dashboards and optimize resource allocation

---

## Reference Links

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Database for PostgreSQL - Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/)
- [Project Requirements](.github/prompts/azure-infrastructure-requirements.prompt.md)

---

**Document Version**: 1.0  
**Last Updated**: November 9, 2025  
**Maintained By**: Platform Engineering Team
