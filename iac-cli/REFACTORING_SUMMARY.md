# Script Refactoring Summary

## What Changed

Consolidated duplicate tenant deployment scripts into parameterized scripts that accept tenant name as input.

## Files Created

1. **`scripts/03-deploy-tenant-resources.sh`** (NEW)
   - Unified tenant resource deployment
   - Replaces: `nbrly/01-deploy-tenant-resources.sh` and `bloom/01-deploy-tenant-resources.sh`
   - Takes tenant as parameter: `nbrly` or `bloom`

2. **`scripts/04-configure-routing.sh`** (NEW)
   - Unified Application Gateway routing configuration
   - Replaces: `nbrly/02-configure-routing.sh` and `bloom/02-configure-routing.sh`
   - Takes tenant as parameter: `nbrly` or `bloom`

3. **`scripts/SCRIPTS_GUIDE.md`** (NEW)
   - Comprehensive documentation for all deployment scripts
   - Usage examples and deployment flow diagrams

## Files Modified

1. **`scripts/02-deploy-tenant-infra.sh`**
   - Updated to call new unified scripts instead of tenant-specific subdirectories
   - Removed dependency on `nbrly/` and `bloom/` subdirectories

## Files Deprecated (Keep for Reference)

These files still exist but are no longer used:
- `scripts/nbrly/01-deploy-tenant-resources.sh`
- `scripts/nbrly/02-configure-routing.sh`
- `scripts/bloom/01-deploy-tenant-resources.sh`
- `scripts/bloom/02-configure-routing.sh`

You can delete these tenant subdirectories once you verify the new scripts work correctly.

## Migration Path

### Before (Old Structure)
```bash
./00-deploy-all.sh astra dev
  └─ Calls: nbrly/01-deploy-tenant-resources.sh
  └─ Calls: nbrly/02-configure-routing.sh
  └─ Calls: bloom/01-deploy-tenant-resources.sh
  └─ Calls: bloom/02-configure-routing.sh
```

### After (New Structure)
```bash
./00-deploy-all.sh astra dev
  └─ Calls: 03-deploy-tenant-resources.sh nbrly
  └─ Calls: 04-configure-routing.sh nbrly
  └─ Calls: 03-deploy-tenant-resources.sh bloom
  └─ Calls: 04-configure-routing.sh bloom
```

## Benefits

1. **No Code Duplication**: One script instead of two identical copies
2. **Easier Maintenance**: Update once, applies to all tenants
3. **Scalability**: Add new tenants by just adding configuration
4. **Consistency**: Same logic for all tenants
5. **Cleaner Structure**: Fewer files, simpler organization

## Testing

Test the new structure:
```bash
# Test full deployment
./scripts/00-deploy-all.sh astra dev

# Or test individual tenants
./scripts/03-deploy-tenant-resources.sh nbrly astra dev
./scripts/04-configure-routing.sh nbrly astra dev

./scripts/03-deploy-tenant-resources.sh bloom astra dev
./scripts/04-configure-routing.sh bloom astra dev
```

## Cleanup (After Verification)

Once you've verified the new scripts work:
```bash
# Remove old tenant-specific subdirectories
rm -rf scripts/nbrly/
rm -rf scripts/bloom/
```

## Adding New Tenants

To add a new tenant (e.g., "demo"):

1. Create configuration:
   ```bash
   mkdir -p config/demo
   cat > config/demo/parameters-dev.json <<EOF
   {
     "tenantName": "demo",
     "caeSubnetPrefix": "10.100.12.0/24",
     "domainName": "demo-dev.astrapia.io"
   }
   EOF
   ```

2. Update validation in both scripts (lines 46 and 44):
   ```bash
   # Change: if [[ ! "$TENANT" =~ ^(nbrly|bloom)$ ]]
   # To:     if [[ ! "$TENANT" =~ ^(nbrly|bloom|demo)$ ]]
   ```

3. Deploy:
   ```bash
   ./scripts/02-deploy-tenant-infra.sh demo astra dev
   ```
