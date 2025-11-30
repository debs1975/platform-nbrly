# Multi-Tenant FastAPI Applications with Azure Container Apps and Application Gateway

This project demonstrates a complete multi-tenant architecture using **Azure Container Apps** and **Azure Application Gateway** to host 4 FastAPI applications across 2 tenants (NBRLY and BLOOM) with proper routing, security, and scalability.

## 🏗️ Architecture Overview

```
Internet → Application Gateway → Container App Environment → Container Apps
    ↓              ↓                        ↓                      ↓
Domain-based    WAF Protection          Internal Network      FastAPI Apps
Routing         SSL Termination        Service Discovery      Health Checks
Path-based      Load Balancing         Auto-scaling          Tenant Isolation
Routing         Health Probes          Managed Identity      Security Hardening
```

### Network Flow
1. **DNS Resolution**: `nbrly-dev.astrapia.io` or `bloom-dev.astrapia.io`
2. **Application Gateway**: Domain-based routing to appropriate tenant
3. **Path-based Routing**: `/app1/*` or `/app2/*` to specific applications
4. **Container Apps**: Internal network with secure communication
5. **FastAPI Applications**: Root path configured for seamless routing

## 📁 Project Structure

```
app-gtwy-apps/
├── README.md                    # This file
├── nbrly/                      # NBRLY tenant applications
│   ├── nbapp1/                 # Primary NBRLY application
│   │   ├── main.py            # FastAPI app with /app1 root_path
│   │   ├── Dockerfile         # Multi-stage build with security
│   │   ├── requirements.txt   # Python dependencies
│   │   └── .dockerignore      # Build optimization
│   └── nbapp2/                 # Secondary NBRLY application  
│       ├── main.py            # FastAPI app with /app2 root_path
│       ├── Dockerfile         # Multi-stage build with security
│       ├── requirements.txt   # Python dependencies
│       └── .dockerignore      # Build optimization
├── bloom/                      # BLOOM tenant applications
│   ├── bmapp1/                 # Primary BLOOM application
│   │   ├── main.py            # FastAPI app with /app1 root_path
│   │   ├── Dockerfile         # Multi-stage build with security
│   │   ├── requirements.txt   # Python dependencies
│   │   └── .dockerignore      # Build optimization
│   └── bmapp2/                 # Secondary BLOOM application
│       ├── main.py            # FastAPI app with /app2 root_path
│       ├── Dockerfile         # Multi-stage build with security
│       ├── requirements.txt   # Python dependencies
│       └── .dockerignore      # Build optimization
├── manifests/                  # Kubernetes/Container Apps YAML manifests
│   ├── README.md              # Manifests documentation
│   ├── nbrly/                 # NBRLY tenant manifests
│   │   ├── nbapp1-containerapp.yaml    # NBRLY App1 Container App manifest
│   │   └── nbapp2-containerapp.yaml    # NBRLY App2 Container App manifest
│   └── bloom/                 # BLOOM tenant manifests
│       ├── bmapp1-containerapp.yaml    # BLOOM App1 Container App manifest
│       └── bmapp2-containerapp.yaml    # BLOOM App2 Container App manifest
└── scripts/                    # Automation scripts
    ├── README.md              # Scripts documentation
    ├── build-push-all.sh      # Build and push all images
    ├── build-push-nbrly.sh    # Build NBRLY tenant images
    ├── build-push-bloom.sh    # Build BLOOM tenant images
    ├── 01-build-push-all.sh   # Numbered: Build and push all images
    ├── 02-build-push-nbrly.sh # Numbered: Build NBRLY tenant images  
    ├── 03-build-push-bloom.sh # Numbered: Build BLOOM tenant images
    ├── 04-deploy-all.sh       # Numbered: Deploy all Container Apps (imperative)
    ├── 05-deploy-nbrly.sh     # Numbered: Deploy NBRLY tenant apps
    ├── 06-deploy-bloom.sh     # Numbered: Deploy BLOOM tenant apps
    ├── 07-deploy-yaml.sh      # Numbered: Deploy using YAML manifests (declarative)
    └── 08-configure-routing.sh   # Configure Application Gateway routing
```

## 🚀 Quick Start

### Prerequisites

1. **Azure CLI** installed and logged in:
   ```bash
   az login
   ```

2. **Docker** installed and running:
   ```bash
   docker --version
   ```

3. **Azure Infrastructure Deployed** using `iac-cli`:
   ```bash
   cd ../iac-cli/scripts
   ./deploy-all.sh
   ```
   
   This creates all required Azure resources:
   - Resource Group: `astra-dev-eastus-rg`
   - Container Registry: `astradevacr`
   - Container App Environment: `astra-dev-eastus-cae`
   - Application Gateway: `astra-dev-eastus-appgtwy`
   - User Managed Identities: `nbrly-dev-uami`, `bloom-dev-uami`
   - Key Vault: `astradeveastuskv`
   - PostgreSQL Servers: `nbrly-dev-psql`, `bloom-dev-psql`
   - Log Analytics Workspace: `astra-dev-eastus-law`

4. **Configuration Files** properly set up (see [Configuration](#-configuration))

### Deployment Steps

1. **Populate Managed Identity IDs**:
   ```bash
   cd scripts/helpers
   ./populate-uami-ids.sh
   ```
   This retrieves actual client IDs and principal IDs from Azure and updates configuration files.

2. **Build and Push Docker Images**:
   ```bash
   cd ../  # Back to scripts directory
   ./build-push-all.sh latest
   ```

3. **Deploy Container Apps** (choose one method):
   ```bash
   # Method 1: Using Azure CLI scripts (imperative)
   ./04-deploy-all.sh latest
   
   # Method 2: Using YAML manifests (declarative)
   ./07-deploy-yaml.sh latest
   ```

4. **Configure Application Gateway Routing**:
   ```bash
   ./08-configure-routing.sh
   ```

5. **Test the Deployment**:
   ```bash
   # Test NBRLY tenant
   curl https://nbrly-dev.astrapia.io/app1/health
   curl https://nbrly-dev.astrapia.io/app2/health
   
   # Test BLOOM tenant
   curl https://bloom-dev.astrapia.io/app1/health
   curl https://bloom-dev.astrapia.io/app2/health
   ```

## 🏢 Tenant Configuration

### NBRLY Tenant
- **Domain**: `nbrly-dev.astrapia.io`
- **Applications**:
  - **nbapp1** (`/app1/*`): Primary NBRLY application with database features
  - **nbapp2** (`/app2/*`): Task management and analytics

### BLOOM Tenant  
- **Domain**: `bloom-dev.astrapia.io`
- **Applications**:
  - **bmapp1** (`/app1/*`): Content management and media processing
  - **bmapp2** (`/app2/*`): Analytics and reporting

## 📋 Deployment Options

### Imperative Deployment (Azure CLI)
Use shell scripts that programmatically create Container Apps:
```bash
./scripts/04-deploy-all.sh latest
```

### Declarative Deployment (YAML Manifests)
Use Kubernetes-style YAML manifests for Container Apps:
```bash
./scripts/07-deploy-yaml.sh latest
```

YAML manifests are located in `manifests/` directory and provide:
- **Version Control**: Track configuration changes in git
- **Infrastructure as Code**: Declarative resource definitions
- **Consistency**: Identical deployments across environments
- **Transparency**: Clear visibility into resource configuration

## 🐳 Container Configuration

All applications use **multi-stage Docker builds** with:
- **Base Image**: Python 3.11 slim
- **Non-root User**: Security hardening with `appuser`
- **Health Checks**: Built-in Docker health checks
- **Optimized Layers**: Multi-stage builds for smaller images
- **Security**: Minimal attack surface, no unnecessary packages

### Environment Variables
Each container is configured with:
```bash
ENVIRONMENT=dev
ROOT_PATH=/app1 or /app2
APP_NAME=TENANT-APPTYPE
TENANT=nbrly or bloom
APP_TYPE=nbapp1, nbapp2, bmapp1, or bmapp2
```

## 🔗 API Endpoints

### Health Check Endpoints (All Apps)
- `GET /health` - Application Gateway health probe
- `GET /health/ready` - Readiness probe for Container Apps
- `GET /health/live` - Liveness probe for Container Apps

### NBRLY Applications
**nbapp1** (`/app1/*`):
- `GET /` - Service information
- `GET /api/info` - Configuration info
- `GET /api/nbrly/services` - NBRLY services
- `GET /api/database/test` - Database connectivity test

**nbapp2** (`/app2/*`):
- `GET /` - Service information
- `GET /api/tasks` - List all tasks
- `POST /api/tasks` - Create new task
- `GET /api/tasks/{task_id}` - Get specific task
- `PUT /api/tasks/{task_id}` - Update task
- `DELETE /api/tasks/{task_id}` - Delete task
- `GET /api/analytics` - Task analytics

### BLOOM Applications  
**bmapp1** (`/app1/*`):
- `GET /` - Service information
- `GET /api/info` - Configuration info
- `GET /api/bloom/services` - BLOOM services
- `GET /api/bloom/content` - Content management info
- `GET /api/database/test` - Database connectivity test

**bmapp2** (`/app2/*`):
- `GET /` - Service information
- `POST /api/analytics/track` - Track analytics event
- `GET /api/analytics/dashboard` - Dashboard data
- `GET /api/analytics/reports` - Available reports
- `GET /api/analytics/realtime` - Real-time metrics

## 🛠️ Development

### Local Development
Each application can be run locally:

```bash
cd nbrly/nbapp1  # or any app directory
pip install -r requirements.txt
python main.py
```

Access the API docs at: `http://localhost:8000/app1/docs`

### Building Individual Images
```bash
# Build NBRLY applications only
./scripts/build-push-nbrly.sh v1.0.0

# Build BLOOM applications only  
./scripts/build-push-bloom.sh v1.0.0
```

### Deploying Individual Tenants
```bash
# Deploy NBRLY tenant only
./scripts/deploy-nbrly.sh v1.0.0

# Deploy BLOOM tenant only
./scripts/deploy-bloom.sh v1.0.0
```

## 🔧 Configuration

### Configuration System

The project uses a centralized JSON-based configuration system with tenant-specific settings:

**Global Configuration** (`config/parameters-dev.json`):
- Shared infrastructure resources (ACR, Key Vault, Log Analytics)
- Resource group and location settings
- Common networking configuration

**Tenant Configurations**:
- `config/nbrly/parameters-dev.json` - NBRLY tenant resources and applications
- `config/bloom/parameters-dev.json` - BLOOM tenant resources and applications

For detailed information on Azure resources integration, see [Azure Resources Integration Guide](docs/azure-resources-integration.md).

### Azure Managed Identities

Each tenant has a dedicated User Assigned Managed Identity (UAMI) for:
- **ACR Authentication**: Secure image pull from Azure Container Registry
- **Key Vault Access**: Retrieve database connection strings

**NBRLY UAMI**: `nbrly-dev-uami`  
**BLOOM UAMI**: `bloom-dev-uami`

Before deployment, populate actual identity IDs:
```bash
cd scripts/helpers
./populate-uami-ids.sh
```

### Azure Key Vault

Database connection strings are securely stored in Azure Key Vault and injected into Container Apps at runtime:

- **Key Vault Name**: `astradeveastuskv`
- **NBRLY Database Secret**: `nbrly-psql-connection-string`
- **BLOOM Database Secret**: `bloom-psql-connection-string`

Container Apps automatically retrieve secrets using their assigned managed identity.

### Azure Container Registry
- **Name**: `astradevacr`
- **URL**: `astradevacr.azurecr.io`
- **Authentication**: Managed Identity (no passwords required)

### Container Apps Naming Convention
- **NBRLY**: `ca-nbrly-nbapp1-dev`, `ca-nbrly-nbapp2-dev`
- **BLOOM**: `ca-bloom-bmapp1-dev`, `ca-bloom-bmapp2-dev`

### Docker Image Names
- **NBRLY**: `nbrly-nbapp1`, `nbrly-nbapp2`
- **BLOOM**: `bloom-bmapp1`, `bloom-bmapp2`

## 🔐 Security Features

### Container Security
- **Non-root execution**: All containers run as `appuser`
- **Minimal base images**: Python 3.11 slim
- **Multi-stage builds**: Smaller attack surface
- **Health checks**: Proper health monitoring
- **Internal networking**: Container Apps use internal ingress

### Application Gateway Security
- **WAF v2**: Web Application Firewall protection
- **SSL termination**: HTTPS enforcement
- **Internal backend**: Secure communication to Container Apps
- **Health probes**: Automatic health monitoring

### Managed Identity Security
- **No credentials in code**: Applications never store ACR or Key Vault credentials
- **Automatic rotation**: Azure handles credential rotation automatically
- **Principle of least privilege**: Each tenant has minimal required permissions
- **Audit trail**: All access logged in Azure Activity Log

## 📊 Monitoring and Logging

### Health Monitoring
- **Application Gateway**: Health probes to `/health` endpoint
- **Container Apps**: Readiness probes to `/health/ready`
- **Container Apps**: Liveness probes to `/health/live`
- **Docker**: Built-in health checks

### Logging
- **Container Apps**: Azure Log Analytics integration
- **Application logs**: Structured logging with timestamps
- **FastAPI**: Request/response logging
- **Health check logs**: Monitoring and debugging

## 🚨 Troubleshooting

### Common Issues

1. **Container Apps Not Starting**:
   ```bash
   # Check logs
   az containerapp logs show --name ca-nbrly-nbapp1-dev --resource-group rg-astrapia-dev
   ```

2. **Application Gateway Health Probe Failures**:
   ```bash
   # Test health endpoint directly
   curl https://CONTAINER-APP-FQDN/health
   ```

3. **Routing Not Working**:
   ```bash
   # Check Application Gateway configuration
   az network application-gateway show --name agw-astrapia-dev --resource-group rg-astrapia-dev
   ```

4. **Image Pull Errors**:
   ```bash
   # Verify ACR access
   az acr login --name astradevacr
   az acr repository list --name astradevacr
   ```

### Debug Commands
```bash
# Container App status
az containerapp show --name ca-nbrly-nbapp1-dev --resource-group rg-astrapia-dev

# Application Gateway backend health
az network application-gateway show-backend-health --name agw-astrapia-dev --resource-group rg-astrapia-dev

# ACR repository tags
az acr repository show-tags --name astradevacr --repository nbrly-nbapp1
```

## 📚 Documentation

- **[Azure Resources Integration](docs/azure-resources-integration.md)**: How app-gtwy-apps integrates with iac-cli infrastructure
- **[Configuration System](docs/configuration-system.md)**: Configuration management and structure
- **[Scripts Documentation](scripts/README.md)**: Detailed script usage
- **[Architecture Design](../docs/sonet/)**: Technical design documents
- **[Deployment Guide](../docs/)**: Step-by-step deployment
- **[API Documentation]**: FastAPI auto-generated docs at `/docs` endpoints

## 🔄 Next Steps

1. **Infrastructure Scripts**: Create scripts for provisioning Azure resources
2. **SSL Certificates**: Configure custom domain SSL certificates
3. **Monitoring Setup**: Application Insights and alerting
4. **Testing Scripts**: Automated testing of routing and functionality
5. **CI/CD Pipeline**: Azure DevOps or GitHub Actions integration

## 🤝 Contributing

1. Follow the existing code structure and naming conventions
2. Add health checks to all new endpoints
3. Use proper error handling and logging
4. Update documentation when adding new features
5. Test all routing scenarios before deployment

## 📄 License

This project follows the organizational licensing and security policies.

---

**Created**: December 2024  
**Architecture**: Multi-tenant Azure Container Apps with Application Gateway  
**Framework**: FastAPI 0.104.1  
**Platform**: Azure Container Apps, Application Gateway WAF v2