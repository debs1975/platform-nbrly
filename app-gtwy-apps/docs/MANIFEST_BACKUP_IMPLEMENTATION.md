# Manifest Backup Implementation Summary

## Overview

Implemented automatic backup functionality for Container App YAML manifests before regeneration. This prevents accidental loss of customizations or previous versions.

## Implementation Date

November 22, 2025

## Changes Made

### 1. Updated Generate Manifests Script

**File**: `scripts/helpers/generate-manifests.sh`

**Added**:
- `backup_manifests()` function that:
  - Creates timestamped backup directory (`.bak/<YYYYMMDD_HHMMSS>/`)
  - Checks for existing manifests before backing up
  - Copies all existing manifests to backup location
  - Preserves directory structure (nbrly/, bloom/)
  - Provides feedback on backup status

**Integration**:
- Backup function is called automatically at the start of `generate_all_manifests()`
- Runs before any manifest generation occurs
- Only backs up if manifests exist (skips on first run)

### 2. Created Backup Directory Structure

**Directory**: `manifests/.bak/`

**Structure**:
```
.bak/
├── README.md                    # Comprehensive backup documentation
└── <YYYYMMDD_HHMMSS>/          # Timestamped backups
    ├── nbrly/
    │   ├── nbapp1-containerapp.yaml
    │   └── nbapp2-containerapp.yaml
    └── bloom/
        ├── bmapp1-containerapp.yaml
        └── bmapp2-containerapp.yaml
```

### 3. Created Documentation

**Files Created**:

1. **`manifests/.bak/README.md`**
   - Purpose and structure of backups
   - When backups are created
   - How to restore from backup
   - Backup retention recommendations
   - Troubleshooting guide
   - Best practices

2. **`manifests/.gitignore`**
   - Excludes `.bak/*` from git (except README)
   - Excludes generated manifests (can be regenerated)
   - Keeps templates and documentation in git

**Files Updated**:

3. **`manifests/README.md`**
   - Updated directory structure diagram to include `.bak/`
   - Added "Manifest Backups" section
   - Documented backup location and restoration process

## Features

### Automatic Backup Triggers

Backups are automatically created when:

1. Running `scripts/helpers/generate-manifests.sh` manually
2. Running `scripts/07-deploy-yaml.sh` (which calls generate-manifests.sh)

### Backup Naming

- **Format**: `YYYYMMDD_HHMMSS`
- **Example**: `20251122_211122` = November 22, 2025 at 9:11:22 PM
- **Benefit**: Chronological sorting, easy identification

### Smart Backup Logic

- **Checks existence**: Only backs up if manifests exist
- **Preserves structure**: Maintains nbrly/bloom directory organization
- **Non-intrusive**: Skips backup on first run (no manifests yet)
- **Clear feedback**: Logs each backed up file and final count

### Git Integration

The `.gitignore` ensures:
- Backup directories are not committed to version control
- Generated manifests are excluded (can be regenerated from templates)
- Templates and configs remain in git (source of truth)

## Testing

### Test Performed

Created and ran comprehensive test script that:
1. Created 4 dummy manifest files
2. Triggered manifest generation (which triggers backup)
3. Verified backup directory creation
4. Confirmed all files were backed up correctly
5. Validated backup timestamp format

### Test Results

✅ **All tests passed**:
- Backup directory created: `.bak/20251122_211122/`
- All 4 manifests backed up successfully
- Directory structure preserved (nbrly/, bloom/)
- Files correctly copied with original content intact
- Timestamped naming working as expected

### Sample Output

```
[2025-11-22 21:11:22] Checking for existing manifests to backup...
[2025-11-22 21:11:22]   Backed up: nbapp1-containerapp.yaml
[2025-11-22 21:11:22]   Backed up: nbapp2-containerapp.yaml
[2025-11-22 21:11:22]   Backed up: bmapp1-containerapp.yaml
[2025-11-22 21:11:22]   Backed up: bmapp2-containerapp.yaml
[SUCCESS] Backed up 4 manifest(s) to: .../manifests/.bak/20251122_211122
```

## Usage

### Automatic (Recommended)

Simply run the deployment or generation scripts as normal:

```bash
# Deployment (includes backup + generation + deploy)
cd scripts
./07-deploy-yaml.sh

# Manual generation only (includes backup)
cd scripts/helpers
./generate-manifests.sh
```

### Restore from Backup

```bash
cd manifests

# List available backups
ls -lt .bak/

# Restore specific backup
cp -r .bak/20251122_211122/nbrly/* nbrly/
cp -r .bak/20251122_211122/bloom/* bloom/
```

## Benefits

1. **Data Safety**: Prevents accidental loss of manifest customizations
2. **Version History**: Maintains history of manifest changes over time
3. **Easy Recovery**: Simple restoration process
4. **Automatic**: No manual intervention required
5. **Non-disruptive**: Doesn't interfere with normal workflow
6. **Clean Git**: Backups excluded from version control

## Maintenance

### Backup Cleanup

Backups are stored locally and should be cleaned periodically:

```bash
# Remove all backups
rm -rf manifests/.bak/*

# Remove backups older than 7 days
find manifests/.bak -type d -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} +

# Remove specific backup
rm -rf manifests/.bak/20251122_211122
```

### Retention Recommendations

- **Development**: Keep last 5-10 backups
- **Production**: Implement external backup solution with longer retention

## Files Modified

1. `scripts/helpers/generate-manifests.sh` - Added backup functionality
2. `manifests/README.md` - Updated documentation

## Files Created

1. `manifests/.bak/README.md` - Backup documentation
2. `manifests/.gitignore` - Git ignore rules
3. `manifests/.bak/` - Backup directory structure

## Technical Details

### Backup Function

```bash
backup_manifests() {
    local backup_dir="$OUTPUT_DIR/.bak"
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    local backup_subdir="$backup_dir/$timestamp"
    
    # Check for existing manifests
    # Create timestamped backup directory
    # Copy all existing manifests
    # Report backup status
}
```

### Integration Point

```bash
generate_all_manifests() {
    # ... logging ...
    
    # Backup existing manifests first
    backup_manifests
    
    # ... generate new manifests ...
}
```

## Future Enhancements

Potential improvements for future consideration:

1. **Backup Retention Policy**: Automatic cleanup of old backups
2. **External Storage**: Option to backup to Azure Blob Storage
3. **Compression**: Compress old backups to save disk space
4. **Backup Validation**: Verify backed up files are valid YAML
5. **Restore Script**: Automated restore helper script
6. **Diff Tool**: Compare current vs backed up manifests

## Related Documentation

- [manifests/README.md](../manifests/README.md) - Main manifest documentation
- [manifests/.bak/README.md](../manifests/.bak/README.md) - Backup-specific guide
- [manifests/templates/README.md](../manifests/templates/README.md) - Template documentation

## Verification

To verify the backup system is working:

```bash
cd manifests

# Generate test manifests (will backup if exist)
cd ../scripts/helpers
./generate-manifests.sh

# Check backup was created
ls -lh ../../manifests/.bak/

# Verify backup contents match originals
diff -r .bak/<latest_timestamp>/nbrly/ nbrly/
```

## Conclusion

The automatic backup system provides a safety net for manifest regeneration while maintaining a clean and efficient workflow. It requires no user intervention and seamlessly integrates with existing deployment processes.

**Status**: ✅ Fully Implemented and Tested

**Impact**: Low-risk enhancement that improves operational safety without affecting normal workflows.
