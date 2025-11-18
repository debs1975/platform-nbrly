# App Gateway Apps - Isolation Guide

## Overview

The `app-gtway-apps` directory is now **self-contained** with all necessary configuration, helpers, and documentation to operate independently from `iac-cli`.

This enables you to:
- ✅ Deploy and manage applications without `iac-cli` present
- ✅ Share this directory with other teams
- ✅ Version control separately
- ✅ Archive and restore independently
- ✅ Test in isolated environments

## Directory Structure

```
app-gtway-apps/
├── config/                          # Application configuration
│   ├── parameters-dev.json         # Environment parameters (copied from iac-cli)
│   └── .generated/                 # Generated state files (optional, for local use)
├── helpers/                         # Reusable bash helper scripts
│   ├── azure-login.sh              # Azure authentication (local copy)
│   └── logging.sh                  # Centralized logging (local copy)
├── creds/                          # Credentials directory
│   └── README.md                   # Setup instructions
├── logs/                           # Execution logs (local)
│   └── README.md                   # Log management guide
├── docs/                           # Documentation
│   └── ISOLATION_GUIDE.md         # This file
├── nbrly/                          # NBRLY tenant applications
│   ├── nbapp1/
│   └── nbapp2/
├── bloom/                          # BLOOM tenant applications
│   ├── bmapp1/
│   └── bmapp2/
├── scripts/                        # Deployment scripts
│   ├── build-push-nbrly.sh
│   ├── build-push-bloom.sh
│   ├── deploy-apps-nbrly.sh
│   ├── deploy-apps-bloom.sh
│   ├── configure-routing-nbrly.sh
│   └── configure-routing-bloom.sh
├── Dockerfile.nbapp1              # Container definitions
├── Dockerfile.nbapp2
├── Dockerfile.bmapp1
├── Dockerfile.bmapp2
├── requirements.txt               # Python dependencies
├── README.md                       # Main documentation
└── QUICK_START_GUIDE.md           # Quick start guide
```

## Usage Modes

### Mode 1: Isolated Deployment (No IaC-CLI Required)

**When to use**: You have the infrastructure already created and just want to deploy/update applications.

#### Setup

1. **Copy credentials** (one-time):
```bash
cd app-gtway-apps/creds
cp ../../iac-cli/creds/azure-credentials-dev.cred ./azure-credentials-dev.cred
# OR create credentials file manually (see creds/README.md)
```

2. **Copy infrastructure state** (or generate locally):
```bash
mkdir -p config/.generated
cp ../../iac-cli/config/.generated/generated-infra-dev.json config/.generated/
```

3. **Deploy applications**:
```bash
cd app-gtway-apps
./scripts/build-push-nbrly.sh dev latest
./scripts/build-push-bloom.sh dev latest
./scripts/deploy-apps-nbrly.sh dev latest
./scripts/deploy-apps-bloom.sh dev latest
./scripts/configure-routing-nbrly.sh
./scripts/configure-routing-bloom.sh
```

### Mode 2: Integrated Deployment (With IaC-CLI)

**When to use**: You need to create/manage both infrastructure and applications.

1. **Deploy infrastructure**:
```bash
cd iac-cli/scripts
./00-deploy-all.sh
```

2. **Deploy applications**:
```bash
cd ../../app-gtway-apps
./scripts/build-push-nbrly.sh dev latest
# ... rest of deployment
```

The scripts automatically fall back to `iac-cli` if local files don't exist.

## Script Behavior

All scripts in `scripts/` follow this configuration resolution pattern:

```
1. Check for local config: app-gtway-apps/config/.generated/generated-infra-dev.json
   ↓ (if not found)
2. Fall back to: ../../iac-cli/config/.generated/generated-infra-dev.json
   ↓ (if not found)
3. Exit with error
```

Similarly for Azure credentials:

```
1. Check for local creds: app-gtway-apps/creds/azure-credentials-dev.cred
   ↓ (if not found)
2. Attempt interactive login or environment variables
```

## Dependencies

### Required System Tools

- `bash` - Shell scripting
- `docker` - Container building and pushing
- `az` CLI - Azure resource management
- `jq` - JSON processing
- `curl` - HTTP requests (for testing)

### Required Azure Resources

- Azure Container Registry (ACR)
- Azure Container App Environment (one per tenant)
- Azure Application Gateway
- Azure Virtual Network

## Local Configuration

### Configure for Isolated Use

To fully isolate `app-gtway-apps` from `iac-cli`:

1. **Create local state file**:
```bash
mkdir -p app-gtway-apps/config/.generated
```

2. **Copy infrastructure details**:
```bash
# Run this after IaC deployment
cp iac-cli/config/.generated/generated-infra-dev.json \
   app-gtway-apps/config/.generated/generated-infra-dev.json
```

3. **Setup credentials**:
```bash
cp iac-cli/creds/azure-credentials-dev.cred \
   app-gtway-apps/creds/azure-credentials-dev.cred
```

### Environment Variables (Alternative to Credentials File)

Instead of credentials file, you can use Azure CLI environment variables:

```bash
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"

# Then run scripts
./scripts/build-push-nbrly.sh dev latest
```

## Multi-Environment Support

To support multiple environments (dev, staging, prod):

1. **Create parameter files** for each environment:
```bash
config/parameters-dev.json
config/parameters-staging.json
config/parameters-prod.json
```

2. **Create credential files**:
```bash
creds/azure-credentials-dev.cred
creds/azure-credentials-staging.cred
creds/azure-credentials-prod.cred
```

3. **Update scripts** to accept environment as first parameter (already supported):
```bash
./scripts/build-push-nbrly.sh staging latest
./scripts/build-push-nbrly.sh prod v1.0
```

## Testing Isolation

### Verify Local Helpers Work

```bash
# Test logging helper
source helpers/logging.sh
setup_logging "test-script" "dev"
log_info "This is a test message"
log_success "Logging works!"

# Test azure-login helper
source helpers/azure-login.sh
azure_login
az account show
```

### Verify Scripts Use Local Paths

```bash
# Check where scripts source helpers from
grep "source" scripts/build-push-nbrly.sh

# Should show: source "${SCRIPT_DIR}/../helpers/logging.sh"
```

### Simulate Isolated Environment

```bash
# Rename iac-cli temporarily to simulate isolated deployment
cd /Users/debashisghosh/Documents/dev/nbrly
mv iac-cli iac-cli.bak

# Try to run app-gtway-apps scripts
cd app-gtway-apps
./scripts/build-push-nbrly.sh dev latest
# Should work using local configs

# Restore iac-cli
cd ..
mv iac-cli.bak iac-cli
```

## Sharing with Other Teams

### Export App-GTWay-Apps

```bash
# Create archive
tar -czf app-gtway-apps-$(date +%Y%m%d).tar.gz \
  --exclude='logs/*' \
  --exclude='creds/azure-credentials*' \
  --exclude='.git' \
  --exclude='__pycache__' \
  app-gtway-apps/

# Share the archive
# Team members extract and follow setup steps
```

### Onboarding New Team Member

```bash
# 1. Extract archive
tar -xzf app-gtway-apps-20251118.tar.gz

# 2. Setup credentials (see creds/README.md)
cp ~/credentials/azure-credentials-dev.cred app-gtway-apps/creds/

# 3. Setup configuration (see config/README.md)
# Get infrastructure state from team
cp ~/infra-state/generated-infra-dev.json app-gtway-apps/config/.generated/

# 4. Deploy applications
cd app-gtway-apps
./scripts/build-push-nbrly.sh dev latest
./scripts/deploy-apps-nbrly.sh dev latest
```

## Troubleshooting

### "Helpers not found" Error

```
Error: scripts/helpers/logging.sh: No such file or directory
```

**Solution**: Helpers have moved to `app-gtway-apps/helpers/`. If this error occurs, your scripts weren't updated. Update them:

```bash
grep -n "iac-cli/scripts/helpers" scripts/*.sh
# Should return no results - all references should be to local helpers
```

### "Configuration file not found"

```
Configuration file not found: app-gtway-apps/config/.generated/generated-infra-dev.json
```

**Solution**: 
1. Copy from iac-cli: `cp iac-cli/config/.generated/generated-infra-dev.json app-gtway-apps/config/.generated/`
2. Or create manually with required infrastructure details

### Scripts Can't Find Docker Images

Verify Dockerfile references are correct:

```bash
cd app-gtway-apps
docker build -f Dockerfile.nbapp1 -t test:latest .
# Should work from app-gtway-apps directory
```

### ACR Login Issues

```bash
# Verify credentials
cat creds/azure-credentials-dev.cred | jq .

# Test manual login
az login --service-principal \
  -u $(jq -r .clientId creds/azure-credentials-dev.cred) \
  -p $(jq -r .clientSecret creds/azure-credentials-dev.cred) \
  --tenant $(jq -r .tenantId creds/azure-credentials-dev.cred)
```

## Migration Checklist

When preparing to isolate `app-gtway-apps`:

- [ ] Create `app-gtway-apps/helpers/` directory
- [ ] Copy `azure-login.sh` from `iac-cli/scripts/helpers/`
- [ ] Copy `logging.sh` from `iac-cli/scripts/helpers/`
- [ ] Update script includes to use local helpers
- [ ] Create `app-gtway-apps/config/` directory
- [ ] Copy `parameters-dev.json` from `iac-cli/config/`
- [ ] Create `app-gtway-apps/creds/` directory with README
- [ ] Create `app-gtway-apps/logs/` directory
- [ ] Test all scripts with local helpers
- [ ] Verify fallback to iac-cli still works
- [ ] Document in team wiki
- [ ] Archive and version for distribution

## Reference

### Helper Files

**Location**: `app-gtway-apps/helpers/`

- `azure-login.sh` - Handles Service Principal and interactive Azure login
- `logging.sh` - Provides logging functions with file and console output

### Configuration Files

**Location**: `app-gtway-apps/config/`

- `parameters-dev.json` - Environment parameters and domain configuration
- `.generated/generated-infra-dev.json` - Infrastructure state (generated by IaC or copied manually)

### Script Files

**Location**: `app-gtway-apps/scripts/`

All scripts support both integrated and isolated modes through fallback configuration resolution.

---

**Last Updated**: November 18, 2025
**Version**: 1.0

For more information, see:
- `README.md` - Main application guide
- `QUICK_START_GUIDE.md` - Deployment instructions
- `creds/README.md` - Credentials setup
- `config/README.md` - Configuration guide
- `logs/README.md` - Logging information
