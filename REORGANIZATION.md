# Repository Reorganization - iac-cli Structure

**Date:** November 10, 2025

## Changes Made

Reorganized the repository to separate infrastructure-as-code (IaC) components into a dedicated `iac-cli` directory.

### Directory Structure Changes

**Before:**
```
platform-nbrly/
├── config/          → Moved to iac-cli/config/
├── creds/           → Moved to iac-cli/creds/
├── docs/            → Moved to iac-cli/docs/
├── scripts/         → Moved to iac-cli/scripts/
├── logs/            → Unchanged
├── sample-app/      → Unchanged
└── README.md        → Updated with new paths
```

**After:**
```
platform-nbrly/
├── iac-cli/                          # NEW - Infrastructure-as-Code directory
│   ├── config/                       # Infrastructure configuration
│   ├── creds/                        # Azure credentials
│   ├── docs/                         # Infrastructure documentation
│   └── scripts/                      # Deployment scripts
│       ├── 01-deploy-networking.sh
│       ├── 02-deploy-security.sh
│       ├── 03-deploy-compute.sh
│       ├── 04-deploy-data.sh
│       ├── 05-deploy-monitoring.sh
│       ├── 06-deploy-ssl.sh
│       ├── 99-verify-deployment.sh
│       ├── test-azure-login.sh
│       └── helpers/
├── logs/                             # Unchanged
├── sample-app/                       # Unchanged (app-specific)
└── README.md                         # Updated paths
```

## Updated Files

### Scripts Updated
All scripts in `iac-cli/scripts/` maintain their relative path references (`../config`, `../creds`, etc.).

Sample-app scripts updated to reference iac-cli:
- `sample-app/scripts/deploy.sh` → References `iac-cli/config/` and `iac-cli/scripts/helpers/`
- `sample-app/scripts/deploy-yaml.sh` → References `iac-cli/config/` and `iac-cli/scripts/helpers/`
- `sample-app/scripts/setup-monitoring.sh` → References `iac-cli/config/` and `iac-cli/scripts/helpers/`
- `sample-app/scripts/deploy-routing.sh` → References `iac-cli/config/` and `iac-cli/scripts/helpers/`

### Documentation Updated
- `README.md` → All script and config references updated to use `iac-cli/` prefix
- `sample-app/README.md` → Infrastructure config paths updated to `iac-cli/config/`
- Repository structure diagram updated to show iac-cli hierarchy

## How to Use After Reorganization

### Deploy Infrastructure
```bash
# All infrastructure scripts are now under iac-cli/scripts/
cd iac-cli/scripts
./01-deploy-networking.sh dev
./02-deploy-security.sh dev
./03-deploy-compute.sh dev
./04-deploy-data.sh dev
./05-deploy-monitoring.sh dev
./06-deploy-ssl.sh dev
```

### Configure Infrastructure
```bash
# Edit infrastructure configuration
vi iac-cli/config/parameters-dev.json

# Manage credentials
vi iac-cli/creds/azure-credentials-dev.cred

# Grant permissions
./iac-cli/scripts/helpers/grant-sp-permissions.sh dev resourcegroup

# Test authentication
./iac-cli/scripts/test-azure-login.sh dev
```

### Deploy Applications
```bash
# Sample app scripts remain in sample-app/scripts/
cd sample-app
./scripts/deploy.sh dev
./scripts/setup-monitoring.sh dev
./scripts/deploy-routing.sh dev
```

## Benefits of New Structure

1. **Clear Separation of Concerns**
   - Infrastructure code (`iac-cli/`) separate from application code (`sample-app/`)
   - Easier to manage infrastructure evolution independently

2. **Future-Proof for Crossplane Migration**
   - When migrating to Crossplane, can create `iac-crossplane/` alongside `iac-cli/`
   - Maintain both approaches during transition

3. **Better Organization**
   - All infrastructure-related files in one location
   - Clearer for teams: infrastructure team owns `iac-cli/`, app teams own `sample-app/`

4. **Scalability**
   - Easy to add more apps (`sample-app-2/`, `frontend/`, `backend/`)
   - Infrastructure remains centralized in `iac-cli/`

## Migration Checklist

- ✅ Created `iac-cli/` directory
- ✅ Moved `config/`, `creds/`, `docs/`, `scripts/` into `iac-cli/`
- ✅ Updated all infrastructure scripts (paths remain relative within iac-cli)
- ✅ Updated sample-app scripts to reference `../../iac-cli/`
- ✅ Updated README.md with new structure
- ✅ Updated sample-app/README.md references
- ✅ Updated repository structure diagram
- ✅ Tested path references

## Notes

- No changes to credential files or configuration content
- All scripts use relative paths, so they work from within their directories
- Git history preserved (files moved, not deleted and recreated)
