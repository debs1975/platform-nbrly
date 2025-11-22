# Application Gateway Apps Implementation Plan

## Executive Summary

This document provides a comprehensive implementation plan for creating a multi-tenant FastAPI application architecture with Azure Container Apps, featuring Application Gateway for ingress and rule-based routing. The implementation follows Azure security best practices and established naming conventions.

## Architecture Overview

### Network Flow Design

```
Internet → DNS (astrapia.io) → Application Gateway → Container App Environment → Container Apps
```

**Domain-based Routing (Application Gateway Level):**
- `nbrly-dev.astrapia.io/*` → nbrly Container App Environment  
- `bloom-dev.astrapia.io/*` → bloom Container App Environment

**Path-based Routing (Container App Environment Level):**
- `/app1` → nbapp1/bmapp1 container apps
- `/app2` → nbapp2/bmapp2 container apps

### Expected Request Flow Examples

1. **https://nbrly-dev.astrapia.io/app1**
   - DNS resolves to Application Gateway public IP
   - Application Gateway routes to nbrly-dev-cae (Container App Environment)
   - Container App Environment routes /app1 to nbapp1 container app

2. **https://bloom-dev.astrapia.io/app2**  
   - DNS resolves to Application Gateway public IP
   - Application Gateway routes to bloom-dev-cae (Container App Environment)
   - Container App Environment routes /app2 to bmapp2 container app

## Application Architecture

### FastAPI Applications Structure

```
app-gtwy-apps/
├── nbrly/
│   ├── nbapp1/     # FastAPI app with root_path="/app1"
│   └── nbapp2/     # FastAPI app with root_path="/app2"
├── bloom/
│   ├── bmapp1/     # FastAPI app with root_path="/app1"  
│   └── bmapp2/     # FastAPI app with root_path="/app2"
├── config/         # Configuration parameters
├── scripts/        # Deployment and build scripts
└── docs/           # Documentation
```

### Container Apps Naming Convention

Following `iac-naming-convention.instructions.md`:

| Resource Type | Tenant | App | Full Name |
|---|---|---|---|
| Container App | nbrly | nbapp1 | `nbrly-dev-nbapp1-ca` |
| Container App | nbrly | nbapp2 | `nbrly-dev-nbapp2-ca` |
| Container App | bloom | bmapp1 | `bloom-dev-bmapp1-ca` |
| Container App | bloom | bmapp2 | `bloom-dev-bmapp2-ca` |

### Container Images Naming

ACR: `astradevacr.azurecr.io`

| Application | Image Tag |
|---|---|
| nbapp1 | `astradevacr.azurecr.io/nbrly-dev-nbapp1:latest` |
| nbapp2 | `astradevacr.azurecr.io/nbrly-dev-nbapp2:latest` |
| bmapp1 | `astradevacr.azurecr.io/bloom-dev-bmapp1:latest` |
| bmapp2 | `astradevacr.azurecr.io/bloom-dev-bmapp2:latest` |

## Implementation Phases

### Phase 1: Application Development
1. Create FastAPI applications with proper path prefixes
2. Implement health check endpoints (health, readiness, liveness)
3. Configure environment variable support
4. Create Dockerfiles and requirements.txt

### Phase 2: Container Management  
1. Build and push Docker images to ACR
2. Create YAML templates for container app deployments
3. Configure managed identities for ACR access
4. Deploy container apps to respective environments

### Phase 3: Routing Configuration
1. Create Container App Environment HTTP route configurations
2. Configure Application Gateway backend pools and routing rules
3. Set up custom domain SSL/TLS certificates
4. Configure health probes and backend settings

### Phase 4: Testing & Documentation
1. End-to-end testing of all routing scenarios
2. Create comprehensive documentation
3. Performance and capacity testing
4. Security validation

## Security Implementation

### Identity & Access Management
- **User-Assigned Managed Identities** per tenant for ACR access
- **Key Vault integration** for secrets and certificates
- **Least privilege principle** for all role assignments

### Network Security
- **Internal-only Container App Environments** (no public access)
- **Application Gateway WAF** for web application firewall protection
- **Private DNS zones** for internal name resolution
- **NSG rules** restricting traffic between subnets

### SSL/TLS Configuration
- **Wildcard certificate** (`*.astrapia.io`) stored in Key Vault
- **SSL termination** at Application Gateway level
- **HTTPS enforcement** with automatic HTTP to HTTPS redirects
- **Backend HTTPS** communication to container apps

## Resource Dependencies

### Existing Infrastructure (Required)
- Virtual Network: `astra-dev-eastus-vnet`
- Application Gateway: `astra-dev-eastus-agw`
- Container App Environments:
  - `nbrly-dev-cae` (in subnet `snet-nbrly-dev-cae`)
  - `bloom-dev-cae` (in subnet `snet-bloom-dev-cae`)
- Azure Container Registry: `astradevacr`
- Key Vault: `astradeveastuskv`
- Managed Identities:
  - `nbrly-dev-uami`
  - `bloom-dev-uami`

### New Resources (To Create)
- 4 FastAPI applications
- 4 Container apps
- HTTP route configurations for each Container App Environment
- Application Gateway routing rules
- Container app deployment YAML files

## Deployment Strategy

### Script Organization
```
app-gtwy-apps/scripts/
├── build-push/
│   ├── build-push-nbrly.sh      # Build & push nbrly apps
│   └── build-push-bloom.sh      # Build & push bloom apps
├── deploy/
│   ├── deploy-apps-nbrly.sh     # Deploy nbrly container apps
│   └── deploy-apps-bloom.sh     # Deploy bloom container apps
├── routing/
│   ├── configure-routing-nbrly.sh   # Configure nbrly routing
│   └── configure-routing-bloom.sh   # Configure bloom routing
└── templates/
    ├── containerapp-template.yaml   # Container app YAML template
    └── routing-template.yaml       # Routing configuration template
```

### Deployment Sequence
1. **Build & Push Images**: Execute build-push scripts for all apps
2. **Deploy Container Apps**: Deploy apps to respective environments
3. **Configure Routing**: Set up path-based routing in Container App Environments
4. **Update Application Gateway**: Configure domain-based routing rules
5. **Verify End-to-End**: Test all routing scenarios

## Monitoring & Observability

### Health Check Endpoints
Each FastAPI app implements:
- `/health` - Basic health check
- `/health/ready` - Readiness probe  
- `/health/live` - Liveness probe

### Application Gateway Health Probes
- **Protocol**: HTTPS
- **Path**: `/health`
- **Interval**: 30 seconds
- **Timeout**: 30 seconds
- **Unhealthy threshold**: 3

### Container App Configuration
- **CPU**: 0.5 vCPU per replica
- **Memory**: 1 GiB per replica  
- **Min replicas**: 2 (High Availability)
- **Max replicas**: 10 (Auto-scaling)
- **Scaling rule**: HTTP concurrency (55 requests/replica)

## Risk Mitigation

### Deployment Risks
- **Rollback strategy**: Keep previous image versions in ACR
- **Blue-green deployment**: Use Container App revisions
- **Health checks**: Comprehensive monitoring at all levels

### Security Risks  
- **Secrets management**: All secrets in Key Vault
- **Network isolation**: Internal-only environments
- **Certificate rotation**: Automated via Key Vault

### Performance Risks
- **Auto-scaling**: Configured based on HTTP concurrency
- **Load testing**: Validate under expected load
- **Monitoring**: Application Insights integration

## Success Criteria

### Functional Requirements
✅ All 4 applications accessible via respective URLs  
✅ Domain-based routing working correctly  
✅ Path-based routing working correctly  
✅ Health checks responding properly  
✅ SSL/TLS certificates working  

### Non-Functional Requirements  
✅ Response time < 500ms for health checks  
✅ Auto-scaling working under load  
✅ Security scans passing  
✅ All secrets properly secured  
✅ Comprehensive monitoring in place  

## Next Steps

1. **Execute Phase 1**: Start with creating the directory structure and FastAPI applications
2. **Iterative testing**: Test each component as it's implemented
3. **Documentation**: Update documentation as implementation progresses
4. **Security review**: Conduct security assessment before production deployment

This implementation follows Azure Well-Architected Framework principles and provides a solid foundation for multi-tenant application deployment with proper security, scalability, and maintainability.