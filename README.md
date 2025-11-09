# platform-nbrly

**Full-stack cloud-native application on Azure** | React + FastAPI + PostgreSQL

---

## Overview

Platform NBRLY is a secure, scalable full-stack web application deployed on Azure Container Apps with enterprise-grade security controls, VNet integration, and private networking.

### Technology Stack
- **Frontend**: React SPA (Single Page Application)
- **Backend**: Python FastAPI REST API
- **Database**: Azure Database for PostgreSQL Flexible Server
- **Container Registry**: Azure Container Registry (ACR)
- **Infrastructure**: Azure Container Apps with VNet integration
- **Secrets**: Azure Key Vault with managed identity authentication
- **Monitoring**: Application Insights + Log Analytics

### Architecture Highlights
✅ **Security-First**: All secrets in Key Vault, managed identity auth, private endpoints  
✅ **VNet-Integrated**: Private networking with NSG rules and isolated subnets  
✅ **Auto-Scaling**: Container Apps scale 0→N based on demand  
✅ **Fully Monitored**: Application Insights, Log Analytics, automated alerts  
✅ **IaC Ready**: Layered deployment scripts, Crossplane migration path

---

## Quick Start

### Prerequisites
- Azure subscription with Contributor access
- Azure CLI 2.50+ installed
- `jq` for JSON parsing (required for all scripts)

### 1. Setup Azure Authentication

**Option A: Service Principal (Recommended for Automation)**

```bash
# Create service principal
az ad sp create-for-rbac \
  --name "sp-nbrly-dev-deployer" \
  --role Contributor \
  --scopes /subscriptions/{your-subscription-id}

# Create credential file from template
cp creds/azure-credentials.example.json creds/azure-credentials-dev.cred

# Edit with your service principal details
vi creds/azure-credentials-dev.cred

# Set secure permissions
chmod 600 creds/azure-credentials-dev.cred

# Test authentication
./scripts/test-azure-login.sh dev
```

**Option B: Interactive Login (Fallback)**

If no credential file is provided, scripts will prompt for interactive browser-based login.

📖 **Detailed Setup**: See [`creds/README.md`](creds/README.md) for complete authentication setup instructions.

**Important: Grant Service Principal Permissions**

Before deploying infrastructure, ensure your service principal has the necessary permissions:

```bash
# Grant Contributor + User Access Administrator roles
# (Required for creating resources and assigning RBAC roles)
./scripts/helpers/grant-sp-permissions.sh dev resourcegroup

# For subscription-level permissions (broader scope):
# ./scripts/helpers/grant-sp-permissions.sh dev subscription
```

💡 **When to run this:**
- First-time setup of service principal
- If you encounter "AuthorizationFailed" errors during deployment
- When the service principal needs to assign RBAC roles (Key Vault, ACR, etc.)

See [`scripts/helpers/grant-sp-permissions.sh`](scripts/helpers/grant-sp-permissions.sh) for details.

### 2. Deploy Infrastructure (Dev Environment)

```bash
# 1. Clone repository
git clone https://github.com/debs1975/platform-nbrly.git
cd platform-nbrly

# 2. Review/update configuration
vi config/parameters-dev.json

# 3. Deploy in layers (40 minutes total)
cd scripts
./01-deploy-networking.sh    # ~5 min  - VNet, subnets, NSG, DNS
./02-deploy-security.sh       # ~3 min  - Key Vault, Managed Identity
./03-deploy-compute.sh        # ~10 min - ACR, Container Apps
./04-deploy-data.sh           # ~15 min - PostgreSQL, Private Endpoint
./05-deploy-monitoring.sh     # ~5 min  - App Insights, Alerts

# 4. Verify deployment
./99-verify-deployment.sh
```

### 3. Deploy Applications

```bash
# Deploy sample FastAPI application
cd sample-app
./scripts/deploy.sh dev

# Configure monitoring and alerts
./scripts/setup-monitoring.sh dev
```

See [`sample-app/README.md`](sample-app/README.md) for detailed application deployment and monitoring setup.

---

## Documentation

### 📄 Architecture & Design
- **[Azure Infrastructure Design (Dev)](docs/azure-infrastructure-design-dev.md)** - Complete architecture, deployment plan, capacity planning, and operational runbook
  - Detailed network capacity planning (supports 200 Container Apps, 30 private endpoints)
  - Compute and database sizing guidelines
  - Cost projections and optimization strategies
  - Growth roadmap and scaling thresholds
- **[Infrastructure Requirements](.github/prompts/azure-infrastructure-requirements.prompt.md)** - Comprehensive service requirements and capacity planning strategy
  - Multi-environment network sizing (dev/staging/production)
  - Container Apps, PostgreSQL, and storage capacity guidelines
  - Detailed cost optimization recommendations

### � Authentication & Security
- **[Azure Authentication Setup](docs/azure-authentication-setup.md)** - Complete implementation guide for automated Azure CLI authentication
  - Service principal setup and credential management
  - Security best practices and file permissions
  - Multi-environment authentication workflow
  - Troubleshooting guide and testing procedures
- **[Credential Management](creds/README.md)** - Detailed setup instructions for Azure service principal authentication
  - Step-by-step service principal creation
  - Credential file format and security requirements
  - Emergency credential rotation procedures

### �🔧 Deployment Scripts
All scripts located in [`scripts/`](scripts/) directory:
- `01-deploy-networking.sh` - VNet, subnets, NSG, Private DNS zones
- `02-deploy-security.sh` - Key Vault, User-Assigned Managed Identity, RBAC
- `03-deploy-compute.sh` - ACR, Container Apps Environment
- `04-deploy-data.sh` - PostgreSQL Flexible Server, Private Endpoint
- `05-deploy-monitoring.sh` - Application Insights, Alert Rules, Diagnostics
- `99-verify-deployment.sh` - Deployment verification and health checks
- `helpers/azure-login.sh` - Automated Azure authentication helper
- `test-azure-login.sh` - Authentication setup testing

### 📊 Configuration
- [`config/parameters-dev.json`](config/parameters-dev.json) - Development environment parameters

### 🔒 Repository Management
- **[Git Ignore Strategy](.gitignore-guide.md)** - Comprehensive guide to version control exclusions
  - Multi-level `.gitignore` strategy (root + app-specific)
  - Protected files and secret management
  - Testing and verification procedures
  - Emergency secret removal procedures

---

## Resource Naming Convention

All resources follow the pattern: `{{project}}-{{env}}-{{region}}-{{resourceType}}`

**Examples (dev environment)**:
- Resource Group: `nbrly-dev-eastus-rg`
- Frontend Container App: `nbrly-dev-eastus-frontend-ca`
- Backend Container App: `nbrly-dev-eastus-backend-ca`
- PostgreSQL Server: `nbrly-dev-eastus-psql`
- Key Vault: `nbrlydeveastuskv` (no hyphens)
- ACR: `nbrlydeveastusacr` (no hyphens)

---

## Security Controls

### Identity & Access
- ✅ User-assigned managed identity for all service-to-service authentication
- ✅ RBAC with least privilege (AcrPull, Key Vault Secrets User)
- ✅ Zero hardcoded secrets (all in Key Vault)

### Network Security
- ✅ VNet integration for all compute resources
- ✅ Private endpoints for database and storage
- ✅ NSG rules enforcing least-privilege access
- ✅ TLS 1.2+ enforced for all connections

### Data Protection
- ✅ Encryption at rest (Azure-managed keys)
- ✅ Encryption in transit (HTTPS/TLS)
- ✅ Automated encrypted backups (7-day retention for dev)

### Monitoring & Compliance
- ✅ Diagnostic logs to Log Analytics
- ✅ Application performance monitoring (App Insights)
- ✅ Automated alerts for failures and anomalies
- ✅ Resource tagging for governance

---

## Cost Estimation (Dev Environment)

**Current Baseline** (2 Container Apps, minimal usage):
| Service | Monthly Cost (USD) |
|---------|-------------------|
| Container Apps (Frontend + Backend) | ~$30 |
| Container Registry (Basic) | $5 |
| PostgreSQL Flexible Server (Burstable B1ms) | $25 |
| Key Vault | $1 |
| Private Endpoint | $8 |
| Log Analytics + App Insights | Free (within 5 GB) |
| **Total Baseline** | **~$69/month** |
| **With Scale-to-Zero** | **~$54/month** |

**At Scale** (150 apps, full development capacity):
| Configuration | Monthly Cost (USD) |
|--------------|-------------------|
| Without Optimizations | $900-1,500 |
| With Scale-to-Zero, Log Archival, Auto-Shutdown | $400-600 |

See [Capacity Planning](docs/azure-infrastructure-design-dev.md#capacity-planning--sizing-strategy) for detailed projections and optimization strategies.

*Costs are estimates based on East US region pricing as of November 2025*

---

## Operational Tasks

### View Application Logs
```bash
# Stream live logs
az containerapp logs show \
  --name nbrly-dev-eastus-backend-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow

# Query historical logs
az monitor log-analytics query \
  --workspace nbrly-dev-eastus-law \
  --analytics-query "ContainerAppConsoleLogs_CL | take 50"
```

### Update Secrets
```bash
# Update database connection string in Key Vault
az keyvault secret set \
  --vault-name nbrlydeveastuskv \
  --name postgres-connection-string \
  --value "postgresql://user:pass@host/db"

# Container Apps will automatically pick up the new secret
```

### Scale Container Apps
```bash
# Manual scaling
az containerapp update \
  --name nbrly-dev-eastus-backend-ca \
  --resource-group nbrly-dev-eastus-rg \
  --min-replicas 1 \
  --max-replicas 10
```

---

## Repository Structure

```
platform-nbrly/
├── .github/
│   ├── copilot-instructions.md          # AI agent guidelines
│   └── prompts/
│       └── azure-infrastructure-requirements.prompt.md
├── config/
│   └── parameters-dev.json              # Dev environment config
├── docs/
│   └── azure-infrastructure-design-dev.md  # Architecture documentation
├── scripts/
│   ├── 01-deploy-networking.sh          # Layer 1: Networking
│   ├── 02-deploy-security.sh            # Layer 2: Security
│   ├── 03-deploy-compute.sh             # Layer 3: Compute (ACR, CAE)
│   ├── 04-deploy-data.sh                # Layer 4: Data
│   ├── 05-deploy-monitoring.sh          # Layer 5: Monitoring
│   └── 99-verify-deployment.sh          # Verification
├── sample-app/                          # Sample FastAPI application
│   ├── main.py                          # FastAPI app with health checks
│   ├── requirements.txt                 # Python dependencies
│   ├── Dockerfile                       # Multi-stage Docker build
│   ├── .dockerignore                    # Docker build exclusions
│   ├── .gitignore                       # Git exclusions
│   ├── scripts/
│   │   ├── deploy.sh                    # Deployment automation
│   │   └── setup-monitoring.sh          # Monitoring & alerts setup
│   ├── docs/
│   │   └── monitoring-alerts.md         # Alert configurations & runbooks
│   └── README.md                        # Application documentation
├── frontend/                            # React application (TBD)
├── backend/                             # FastAPI application (TBD)
└── README.md
```

---

## Next Steps

- [x] Infrastructure deployment scripts (5 layers)
- [x] Sample FastAPI application with deployment automation
- [x] Monitoring and alerting configuration
- [x] Comprehensive documentation and runbooks
- [ ] Production React frontend application
- [ ] Production FastAPI backend microservices
- [ ] CI/CD pipelines (GitHub Actions or Azure DevOps)
- [ ] Staging and production environment deployment
- [ ] Load testing and performance optimization
- [ ] Crossplane migration for multi-cloud IaC
- [ ] Build production frontend React application
- [ ] Build production backend FastAPI application with database connectivity
- [ ] Set up CI/CD pipeline (GitHub Actions or Azure DevOps)
- [ ] Configure custom domains and SSL certificates
- [ ] Implement staging and production environments
- [ ] Migrate to Crossplane for GitOps-based infrastructure management

---

## Support & Contributing

- **Issues**: Report bugs or request features via GitHub Issues
- **Documentation**: See [`docs/`](docs/) directory for detailed guides
- **Architecture Questions**: Refer to [Infrastructure Requirements](.github/prompts/azure-infrastructure-requirements.prompt.md)

---

**Last Updated**: November 9, 2025  
**Maintainer**: Platform Engineering Team  
**License**: MIT

