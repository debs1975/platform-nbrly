# Application Gateway Apps - Detailed TODO Implementation Plan

## Phase 1: Foundation Setup (Items 1-5)

### ✅ TODO 1: Create app-gtwy-apps Directory Structure
**Status**: Ready to implement  
**Estimated Time**: 30 minutes  
**Dependencies**: None

**Directory Structure to Create:**
```
app-gtwy-apps/
├── nbrly/
│   ├── nbapp1/
│   ├── nbapp2/
│   └── README.md
├── bloom/
│   ├── bmapp1/
│   ├── bmapp2/
│   └── README.md
├── config/
│   ├── parameters-dev.json
│   ├── nbrly/
│   │   └── parameters-dev.json
│   └── bloom/
│       └── parameters-dev.json
├── scripts/
│   ├── build-push/
│   ├── deploy/
│   ├── routing/
│   ├── templates/
│   └── helpers/
├── docs/
├── manifests/
│   ├── nbrly/
│   └── bloom/
└── README.md
```

### ✅ TODO 2-5: Create FastAPI Applications
**Pattern**: Each application follows the same structure with different root paths

**For nbapp1** (root_path="/app1"):
```python
# main.py structure
- FastAPI app with root_path="/app1" 
- Health endpoints: /health, /health/ready, /health/live
- Environment variable support
- Database connection handling
- CORS configuration
- Logging configuration
```

**Files per application:**
- `main.py` - FastAPI application code
- `requirements.txt` - Python dependencies  
- `Dockerfile` - Multi-stage container build
- `.dockerignore` - Build optimization
- `README.md` - Application documentation

## Phase 2: Container Management (Items 6-8)

### ✅ TODO 6: Docker Build and Push Scripts
**Components needed:**

1. **Individual build scripts:**
   - `build-push-nbrly.sh` - Builds nbapp1 & nbapp2
   - `build-push-bloom.sh` - Builds bmapp1 & bmapp2

2. **Master build script:**
   - `build-push-all.sh` - Orchestrates all builds

3. **Image naming convention:**
   ```
   astradevacr.azurecr.io/nbrly-dev-nbapp1:latest
   astradevacr.azurecr.io/nbrly-dev-nbapp2:latest  
   astradevacr.azurecr.io/bloom-dev-bmapp1:latest
   astradevacr.azurecr.io/bloom-dev-bmapp2:latest
   ```

### ✅ TODO 7: Container App Deployment YAML Templates
**Templates needed:**

1. **Base template:** `containerapp-template.yaml`
   - Parameterized with environment variables
   - Managed identity configuration
   - Resource limits and scaling rules
   - Health probe configuration

2. **Generated YAMLs per app:**
   ```
   manifests/nbrly/nbrly-dev-nbapp1-ca.yaml
   manifests/nbrly/nbrly-dev-nbapp2-ca.yaml
   manifests/bloom/bloom-dev-bmapp1-ca.yaml  
   manifests/bloom/bloom-dev-bmapp2-ca.yaml
   ```

### ✅ TODO 8: Container App Deployment Scripts
**Scripts needed:**

1. **Individual deployment scripts:**
   - `deploy-apps-nbrly.sh` - Deploys nbrly apps
   - `deploy-apps-bloom.sh` - Deploys bloom apps

2. **Template generation script:**
   - `generate-manifests.sh` - Creates YAML files from templates

## Phase 3: Routing Configuration (Items 9-11)

### ✅ TODO 9: Container App Environment Routing YAML
**HTTP Route Configurations:**

1. **NBRLY routing:** `nbrly-route-config.yaml`
   ```yaml
   routes:
     - match: pathSeparatedPrefix: "/app1"
       action: prefixRewrite: "/"
       targets: containerApp: "nbrly-dev-nbapp1-ca"
     - match: pathSeparatedPrefix: "/app2"  
       action: prefixRewrite: "/"
       targets: containerApp: "nbrly-dev-nbapp2-ca"
   ```

2. **BLOOM routing:** `bloom-route-config.yaml`
   ```yaml  
   routes:
     - match: pathSeparatedPrefix: "/app1"
       action: prefixRewrite: "/"
       targets: containerApp: "bloom-dev-bmapp1-ca"
     - match: pathSeparatedPrefix: "/app2"
       action: prefixRewrite: "/"  
       targets: containerApp: "bloom-dev-bmapp2-ca"
   ```

### ✅ TODO 10: Routing Configuration Scripts
**Scripts for Container App Environment routing:**

1. **configure-routing-nbrly.sh**
   - Creates HTTP route configuration for nbrly-dev-cae
   - Configures custom domain nbrly-dev.astrapia.io
   - Sets up SSL certificate binding

2. **configure-routing-bloom.sh**
   - Creates HTTP route configuration for bloom-dev-cae
   - Configures custom domain bloom-dev.astrapia.io
   - Sets up SSL certificate binding

### ✅ TODO 11: Application Gateway Routing Scripts  
**Application Gateway configuration:**

1. **configure-app-gateway.sh**
   - Creates backend pools for each Container App Environment
   - Configures listeners for each domain
   - Sets up routing rules
   - Configures health probes
   - Updates backend settings

2. **Backend pool configuration:**
   ```bash
   # NBRLY backend pool -> nbrly-dev-cae static IP
   # BLOOM backend pool -> bloom-dev-cae static IP
   ```

## Phase 4: Documentation & Testing (Item 12)

### ✅ TODO 12: Implementation Documentation
**Documentation deliverables:**

1. **Deployment Guide:** Step-by-step deployment instructions
2. **Testing Guide:** End-to-end testing procedures  
3. **Troubleshooting Guide:** Common issues and solutions
4. **Architecture Overview:** Updated architecture diagrams
5. **API Documentation:** OpenAPI specs for all applications

## Detailed Implementation Sequence

### Step 1: Foundation (Day 1)
```bash
# Execute TODO 1
mkdir -p app-gtwy-apps/{nbrly/{nbapp1,nbapp2},bloom/{bmapp1,bmapp2}}
mkdir -p app-gtwy-apps/{config/{nbrly,bloom},scripts/{build-push,deploy,routing,templates,helpers},docs,manifests/{nbrly,bloom}}

# Execute TODOs 2-5 (Parallel)
# Create all 4 FastAPI applications
```

### Step 2: Container Build (Day 1-2)  
```bash
# Execute TODO 6
# Create and test Docker build scripts

# Execute TODO 7  
# Create YAML templates

# Execute TODO 8
# Create deployment scripts
```

### Step 3: Routing Setup (Day 2-3)
```bash
# Execute TODO 9
# Create routing YAML configurations

# Execute TODO 10
# Create Container App Environment routing scripts

# Execute TODO 11  
# Create Application Gateway configuration scripts
```

### Step 4: Integration Testing (Day 3-4)
```bash
# Execute TODO 12
# Create documentation and run end-to-end tests

# Test all routing scenarios:
curl https://nbrly-dev.astrapia.io/app1/health
curl https://nbrly-dev.astrapia.io/app2/health
curl https://bloom-dev.astrapia.io/app1/health  
curl https://bloom-dev.astrapia.io/app2/health
```

## Risk Assessment & Mitigation

### High Risk Items
1. **SSL Certificate Configuration** (TODOs 10-11)
   - **Risk**: Certificate binding issues
   - **Mitigation**: Test with existing wildcard cert first

2. **Container App Environment Routing** (TODO 9)
   - **Risk**: Path rewriting configuration  
   - **Mitigation**: Start with simple prefix matching

3. **Application Gateway Backend Configuration** (TODO 11)
   - **Risk**: Health probe connectivity
   - **Mitigation**: Validate Container App Environment accessibility

### Medium Risk Items  
1. **Docker Image Build** (TODO 6)
   - **Risk**: ACR authentication issues
   - **Mitigation**: Validate ACR access before build

2. **Container App Deployment** (TODO 8)  
   - **Risk**: Managed identity configuration
   - **Mitigation**: Test identity access to ACR and Key Vault

## Success Validation Checklist

### Functional Testing
- [ ] All 4 applications build successfully
- [ ] All 4 container apps deploy successfully  
- [ ] All health endpoints respond correctly
- [ ] Domain-based routing works (AGW level)
- [ ] Path-based routing works (CAE level)
- [ ] SSL certificates function properly
- [ ] Auto-scaling triggers correctly

### Security Testing  
- [ ] Managed identities have least privilege access
- [ ] All secrets retrieved from Key Vault
- [ ] Container apps are internal-only
- [ ] WAF policies are active
- [ ] Network isolation is enforced

### Performance Testing
- [ ] Response times < 500ms for health checks
- [ ] Auto-scaling works under load
- [ ] Resource utilization is optimized
- [ ] No memory leaks or CPU spikes

This detailed TODO plan provides a clear roadmap for implementing the Application Gateway apps with proper sequencing, risk mitigation, and validation criteria.