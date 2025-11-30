# Routing Scripts Analysis and Reorganization

## Executive Summary

**Found Issue**: Two identical scripts serving the same purpose with different naming conventions.

**Recommendation**: Delete `scripts/configure-routing.sh` (non-numbered) and keep only `scripts/08-configure-routing.sh` (numbered, follows naming convention).

---

## Current State

### Routing Scripts Inventory

| Script | Location | Lines | Purpose | Status |
|--------|----------|-------|---------|--------|
| `configure-routing.sh` | `scripts/` | 430 | Configure App Gateway routing via CLI | ❌ **DUPLICATE** |
| `08-configure-routing.sh` | `scripts/` | 430 | Configure App Gateway routing via CLI | ✅ **KEEP** |
| `deploy-routing-yaml.sh` | `manifests/routing/` | 391 | Deploy routing from YAML manifests | ✅ **KEEP** |

### Key Findings

#### 1. **Identical Duplicates**
```bash
$ diff -u configure-routing.sh 08-configure-routing.sh
# No output = Files are identical
```

Both files are **100% identical** with 430 lines each. They:
- Have the same comments
- Load the same configurations
- Implement the same functions
- Use the same logic

#### 2. **Naming Convention**

The workspace uses a **numbered sequence** for scripts:
```
01-build-push-all.sh
02-build-push-nbrly.sh
03-build-push-bloom.sh
04-deploy-all.sh
05-deploy-nbrly.sh
06-deploy-bloom.sh
07-deploy-yaml.sh
08-configure-routing.sh      ← Follows convention
configure-routing.sh         ← Breaks convention
```

#### 3. **References Analysis**

**Scripts referencing these files:**
- `scripts/deploy-all.sh` → references `configure-routing.sh`
- `scripts/04-deploy-all.sh` → references `configure-routing.sh`
- `scripts/deploy-yaml.sh` → references `configure-routing.sh`
- `scripts/07-deploy-yaml.sh` → references `configure-routing.sh`

**Documentation referencing these files:**
- `README.md` → references `configure-routing.sh`
- `manifests/README.md` → references `configure-routing.sh`
- `manifests/routing/README.md` → references `configure-routing.sh`
- `docs/configuration-system.md` → references `configure-routing.sh`
- `docs/hostname-configuration.md` → references `08-configure-routing.sh`

**Mixed references indicate confusion!**

---

## Script Purposes

### `08-configure-routing.sh` (and its duplicate `configure-routing.sh`)

**Purpose**: Configure Application Gateway routing using Azure CLI commands

**What it does**:
1. Loads configuration from `config/infra-dev.json`
2. Gets Container App FQDNs from Azure
3. Creates backend pools pointing to Container Apps
4. Creates HTTP settings with health probes
5. Creates URL path maps for path-based routing (`/app1/*`, `/app2/*`)
6. Creates HTTP listeners for domain-based routing
7. Creates routing rules combining both

**Method**: **Imperative** - Uses Azure CLI commands directly

**Example**:
```bash
az network application-gateway address-pool create \
    --gateway-name astra-dev-eastus-agw \
    --resource-group astra-dev-eastus-rg \
    --name pool-nbrly-app1 \
    --servers ca-nbrly-nbapp1-dev.internal.azurecontainerapps.io
```

### `manifests/routing/deploy-routing-yaml.sh`

**Purpose**: Deploy routing configuration based on YAML manifest definitions

**What it does**:
1. Processes YAML manifests (`nbrly-routing.yaml`, `bloom-routing.yaml`)
2. Extracts configuration from YAML
3. Converts YAML definitions to Azure CLI commands
4. Applies the configuration

**Method**: **Declarative-to-Imperative** - Reads YAML, executes CLI commands

**Key Difference**: 
- Reads from YAML manifests as a source of truth
- Same outcome as `configure-routing.sh` but driven by YAML definitions
- Note in script header: *"Azure CLI doesn't directly support Application Gateway YAML deployment"*

**Status**: Less maintained, uses hardcoded values instead of config files

---

## Analysis by Category

### 1. Functionality Overlap

| Feature | 08-configure-routing.sh | deploy-routing-yaml.sh |
|---------|-------------------------|------------------------|
| Backend pools | ✅ Creates | ✅ Creates |
| HTTP settings | ✅ Creates | ✅ Creates |
| URL path maps | ✅ Creates | ✅ Creates |
| HTTP listeners | ✅ Creates | ✅ Creates |
| Routing rules | ✅ Creates | ✅ Creates |
| Config source | config/infra-dev.json | YAML manifests |
| Domain config | From infra config | Hardcoded |
| Maintenance | ✅ Active | ⚠️ Less active |

### 2. Configuration Sources

**`08-configure-routing.sh`**:
```bash
# From config/infra-dev.json
RESOURCE_GROUP=$(get_infra_value "$ENV" ".resources.resourceGroup.name")
APP_GATEWAY_NAME=$(get_infra_value "$ENV" ".resources.applicationGateway.name")
NBRLY_DOMAIN=$(get_infra_value "$ENV" ".resources.tenants.nbrly.hostName")
BLOOM_DOMAIN=$(get_infra_value "$ENV" ".resources.tenants.bloom.hostName")
```

**`deploy-routing-yaml.sh`**:
```bash
# Hardcoded values
RESOURCE_GROUP="rg-astrapia-dev"
APP_GATEWAY_NAME="agw-astrapia-dev"
# Hardcoded in script
domain="nbrly-dev.astrapia.io"  # or "bloom-dev.astrapia.io"
```

### 3. Maintenance Status

**Active and Updated**:
- ✅ `08-configure-routing.sh` - Recently updated with correct hostname config

**Less Active**:
- ⚠️ `deploy-routing-yaml.sh` - Uses hardcoded values, not following config system
- ⚠️ `configure-routing.sh` - Duplicate of numbered version

---

## Recommendations

### Immediate Actions

#### 1. **Delete Duplicate Script** ✅ HIGH PRIORITY

**Delete**: `scripts/configure-routing.sh`
**Keep**: `scripts/08-configure-routing.sh`

**Reason**:
- 100% identical to numbered version
- Breaks naming convention
- Causes confusion (mixed references)
- No unique functionality

#### 2. **Update All References** ✅ HIGH PRIORITY

Update scripts and documentation to use `08-configure-routing.sh`:

**Scripts to update**:
- `scripts/deploy-all.sh`
- `scripts/04-deploy-all.sh`
- `scripts/deploy-yaml.sh`
- `scripts/07-deploy-yaml.sh`

**Documentation to update**:
- `README.md`
- `manifests/README.md`
- `manifests/routing/README.md`
- `docs/configuration-system.md`
- `docs/configuration-migration.md`
- `docs/azure-resources-integration.md`
- `INTEGRATION_CHECKLIST.md`

**Files already correct**:
- `docs/hostname-configuration.md` - Already references `08-configure-routing.sh`

#### 3. **Decision on deploy-routing-yaml.sh** ⚠️ MEDIUM PRIORITY

**Option A: Update and Keep** (Recommended if you want YAML-driven approach)
- Update to use `config-loader.sh` instead of hardcoded values
- Align with centralized configuration system
- Useful for declarative infrastructure approach

**Option B: Archive or Delete** (Recommended if CLI approach is sufficient)
- Move to `manifests/routing/archive/` or delete
- Simpler maintenance (one script instead of two)
- Current preference is CLI-based approach

**Recommendation**: **Option B - Archive**
- CLI approach (`08-configure-routing.sh`) is actively maintained
- YAML approach doesn't add value (Azure CLI doesn't natively support App Gateway YAML)
- Reduces maintenance burden
- YAML manifests can be kept for documentation purposes

---

## Proposed File Structure

### Before (Current)
```
scripts/
├── configure-routing.sh          ❌ DELETE (duplicate)
├── 08-configure-routing.sh       ✅ KEEP (primary)
└── ...

manifests/routing/
├── deploy-routing-yaml.sh        ⚠️ ARCHIVE or UPDATE
├── nbrly-routing.yaml            ✅ KEEP (documentation)
├── bloom-routing.yaml            ✅ KEEP (documentation)
└── application-gateway-complete.yaml ✅ KEEP (documentation)
```

### After (Recommended)
```
scripts/
├── 08-configure-routing.sh       ✅ PRIMARY routing script
└── ...

manifests/routing/
├── archive/                      📁 NEW
│   └── deploy-routing-yaml.sh   📦 ARCHIVED (reference only)
├── nbrly-routing.yaml            ✅ KEEP (documentation)
├── bloom-routing.yaml            ✅ KEEP (documentation)
└── application-gateway-complete.yaml ✅ KEEP (documentation)
```

---

## Implementation Plan

### Phase 1: Remove Duplicate (Immediate)

1. **Backup the duplicate** (safety measure)
   ```bash
   cp scripts/configure-routing.sh scripts/archive/configure-routing.sh.bak
   ```

2. **Update all script references**
   - Change `configure-routing.sh` → `08-configure-routing.sh`
   - Files: deploy-all.sh, 04-deploy-all.sh, deploy-yaml.sh, 07-deploy-yaml.sh

3. **Update all documentation references**
   - Change `configure-routing.sh` → `08-configure-routing.sh`
   - Files: README.md, manifests/README.md, routing/README.md, docs/*.md

4. **Delete the duplicate**
   ```bash
   rm scripts/configure-routing.sh
   ```

5. **Test the workflow**
   ```bash
   cd scripts
   ./08-configure-routing.sh
   ```

### Phase 2: Archive YAML Deployment Script (Optional)

1. **Create archive directory**
   ```bash
   mkdir -p manifests/routing/archive
   ```

2. **Move deprecated script**
   ```bash
   mv manifests/routing/deploy-routing-yaml.sh manifests/routing/archive/
   ```

3. **Add archive README**
   - Document why script was archived
   - Point to current approach (`08-configure-routing.sh`)

4. **Update routing/README.md**
   - Remove references to `deploy-routing-yaml.sh`
   - Update deployment instructions

---

## Testing Plan

### Test 1: Verify Script Works
```bash
cd scripts
./08-configure-routing.sh
# Should complete successfully
```

### Test 2: Verify References
```bash
# Check no references to old name remain
grep -r "configure-routing.sh" . --exclude-dir=archive
# Should only show references to 08-configure-routing.sh
```

### Test 3: End-to-End Deployment
```bash
cd scripts
./01-build-push-all.sh
./04-deploy-all.sh
./08-configure-routing.sh
# Verify complete workflow works
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing scripts | Low | Medium | Update all references before deletion |
| User confusion | Low | Low | Clear documentation updates |
| Lost functionality | None | None | Scripts are identical |
| Rollback needed | Very Low | Low | Keep backup in archive/ |

---

## Benefits After Reorganization

1. **Clarity**: One routing script with clear, numbered naming
2. **Consistency**: All scripts follow numbered convention
3. **Maintainability**: Single source of truth for routing logic
4. **Documentation**: Clear references without confusion
5. **Simplicity**: Fewer files to maintain

---

## Summary

### Current State
- ❌ Two identical routing scripts (duplication)
- ❌ Mixed naming conventions (numbered vs non-numbered)
- ❌ Confusing references in code and docs
- ⚠️ Additional YAML-based script with limited value

### Recommended State
- ✅ Single routing script: `08-configure-routing.sh`
- ✅ Consistent numbered naming
- ✅ Clear references throughout
- ✅ Simplified maintenance

### Action Items
1. Delete `scripts/configure-routing.sh`
2. Update all references to use `08-configure-routing.sh`
3. Archive `manifests/routing/deploy-routing-yaml.sh`
4. Update documentation

### Estimated Effort
- **Phase 1** (Remove duplicate): 30 minutes
- **Phase 2** (Archive YAML script): 15 minutes
- **Testing**: 15 minutes
- **Total**: ~1 hour

---

## Conclusion

The existence of `configure-routing.sh` and `08-configure-routing.sh` as identical files is clearly an oversight from the script renaming/numbering exercise. The numbered version should be retained as it follows the established naming convention, and all references should be updated accordingly.

The `deploy-routing-yaml.sh` script, while conceptually interesting for a declarative approach, doesn't add practical value since Azure CLI doesn't natively support Application Gateway YAML deployment. It should be archived for reference but removed from active use.

**Recommendation**: Proceed with cleanup to eliminate confusion and maintain a clean, consistent codebase.
