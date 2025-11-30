# Archived Scripts

This directory contains scripts that have been deprecated or replaced by newer versions.

## Archive Contents

### `configure-routing.sh` (Archived: 2025-11-22)

**Reason for archival**: Duplicate of `08-configure-routing.sh`

**Background**:
During the script reorganization to implement numbered naming convention (01-, 02-, etc.), this script was copied to `08-configure-routing.sh` but the original was not deleted, creating unnecessary duplication.

**Replacement**: Use `../08-configure-routing.sh` instead

**Differences**: None - the files were 100% identical (430 lines each)

**Migration Path**:
All references in scripts and documentation have been updated to use `08-configure-routing.sh`:
- ✅ `scripts/deploy-all.sh`
- ✅ `scripts/04-deploy-all.sh`
- ✅ `scripts/deploy-yaml.sh`
- ✅ `scripts/07-deploy-yaml.sh`
- ✅ `README.md`
- ✅ `manifests/README.md`
- ✅ `docs/configuration-system.md`
- ✅ All other documentation

**Safe to delete**: Yes, after verification period (recommend keeping for 30 days)

---

### `deploy-all.sh` (Archived: 2025-11-22)

**Reason for archival**: Duplicate of `04-deploy-all.sh`

**Background**:
During the script reorganization to implement numbered naming convention, this unnumbered script remained while the numbered version existed, creating unnecessary duplication.

**Replacement**: Use `../04-deploy-all.sh` instead

**Differences**: None - the files were 100% identical (7957 bytes each)

**Migration Path**: All references updated to use `04-deploy-all.sh`

**Safe to delete**: Yes, after verification period (recommend keeping for 30 days)

---

### `deploy-yaml.sh` (Archived: 2025-11-22)

**Reason for archival**: Duplicate of `07-deploy-yaml.sh`

**Background**:
During the script reorganization to implement numbered naming convention, this unnumbered script remained while the numbered version existed, creating unnecessary duplication.

**Replacement**: Use `../07-deploy-yaml.sh` instead

**Differences**: None - the files were 100% identical (10683 bytes each)

**Migration Path**: All references updated to use `07-deploy-yaml.sh`

**Safe to delete**: Yes, after verification period (recommend keeping for 30 days)

---

## Why Archive Instead of Delete?

Scripts are moved to `archive/` rather than deleted immediately to:

1. **Safety Net**: Allow rollback if issues are discovered
2. **Reference**: Maintain history for understanding past approaches
3. **Verification**: Confirm no hidden dependencies exist
4. **Transition Period**: Give teams time to update workflows

## Retention Policy

**Recommended**: Delete archived files after 30-90 days of successful operation with replacements

**Verification before deletion**:
```bash
# Ensure no references to archived scripts exist
grep -r "configure-routing.sh" ../.. --exclude-dir=archive

# Should return no results (except in this README)
```

## Restoration (if needed)

To restore an archived script temporarily:
```bash
cp archive/configure-routing.sh ../configure-routing.sh
```

**Note**: Consider why restoration is needed - likely indicates a missed reference that should be updated instead.

---

Last Updated: 2025-11-22
