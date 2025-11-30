# Generated Container App Manifests

This directory contains **auto-generated YAML manifests** for Azure Container Apps deployment.

## ⚠️ Important

**DO NOT edit files in this directory directly!** All files here are automatically generated and will be overwritten.

## How It Works

Manifests are generated from templates using the configuration system:

```
manifests/templates/*.yaml.template
    + config/infra-dev.json
    + config/nbrly/parameters-dev.json
    + config/bloom/parameters-dev.json
    ↓ 
    generate-manifests.sh
    ↓
manifests.generated/*.yaml (THIS DIRECTORY)
```

## Generated Files

**Container Apps:**
- `nbrly-nbapp1.yaml` - NBRLY tenant, app1 (basic container app)
- `nbrly-nbapp2.yaml` - NBRLY tenant, app2 (with database)
- `bloom-bmapp1.yaml` - BLOOM tenant, app1 (basic container app)
- `bloom-bmapp2.yaml` - BLOOM tenant, app2 (with database)

**Application Gateway Routing:**
- `routing/nbrly-routing.yaml` - NBRLY routing configuration
- `routing/bloom-routing.yaml` - BLOOM routing configuration
- `routing/application-gateway-complete.yaml` - Complete AppGW config

## Making Changes

To modify Container App configuration:

1. **Edit templates**: `manifests/templates/*.yaml.template`
2. **Edit configuration**: `config/*/parameters-dev.json`
3. **Regenerate**: Run `./scripts/helpers/generate-manifests.sh`
4. **Deploy**: Run `./scripts/07-deploy-yaml.sh`

## Git Ignored

All `*.yaml` files in this directory are git-ignored to prevent:
- Committing auto-generated files
- Merge conflicts on generated content
- Storing sensitive values (UAMI client IDs, etc.)

Templates and configuration files are version-controlled instead.

## Backup

Before regeneration, existing manifests are automatically backed up to:
```
../manifests/.bak/<timestamp>/
```

This allows recovery if needed.

## Deployment

These manifests are used by:
```bash
cd scripts
./07-deploy-yaml.sh [TAG]
```

The deployment script:
1. Calls `generate-manifests.sh` to regenerate manifests
2. Updates image tags and UAMI client IDs
3. Deploys each Container App using Azure CLI

---

**Last Generated**: Auto-updated on each deployment
**Source Templates**: `../templates/`
**Configuration**: `../../config/`
