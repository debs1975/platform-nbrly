# Quick Start Guide

## Prerequisites
- Azure CLI installed and authenticated
- Docker installed (for build-push.sh)
- jq installed: `brew install jq`

## Deployment Commands

### Deploy App1 to Dev (Complete)
```bash
cd sample-app/scripts
./deploy.sh app1 dev
```

### Deploy App2 to Dev (Complete)
```bash
cd sample-app/scripts
./deploy.sh app2 dev
```

### Deploy Both Apps
```bash
cd sample-app/scripts
./deploy.sh app1 dev
./deploy.sh app2 dev
```

### Deploy Specific Version to Production
```bash
cd sample-app/scripts
./build-push.sh app1 prod v1.2.3
./deploy-app.sh app1 prod v1.2.3
```

## Important Notes

⚠️ **App name is REQUIRED** - No defaults assumed
- Valid app names: `app1`, `app2`
- Must be specified as first parameter
- Scripts will error if app name is missing or invalid

## Script Usage

### build-push.sh
```bash
./build-push.sh <app-name> [environment] [tag]
```
**Required:** app-name (app1 or app2)  
**Optional:** environment (default: dev), tag (default: from config)

### deploy-app.sh
```bash
./deploy-app.sh <app-name> [environment] [image-tag]
```
**Required:** app-name (app1 or app2)  
**Optional:** environment (default: dev), image-tag (default: latest)

### deploy.sh
```bash
./deploy.sh <app-name> [environment] [tag]
```
**Required:** app-name (app1 or app2)  
**Optional:** environment (default: dev), tag (default: latest)

## Error Examples

❌ **Wrong:**
```bash
./build-push.sh dev         # Missing required app name
./deploy-app.sh             # Missing required app name
./deploy.sh prod v1.2.3     # Missing required app name
```

✅ **Correct:**
```bash
./build-push.sh app1 dev
./deploy-app.sh app2
./deploy.sh app1 prod v1.2.3
```

## Configuration Files

Each app has its own configuration:
- `config/app1-config-dev.json` - App1 dev configuration
- `config/app2-config-dev.json` - App2 dev configuration
- `config/infra-config-dev.json` - Shared infrastructure configuration

## Next Steps

For detailed documentation, see:
- [scripts/README.md](scripts/README.md) - Complete script reference
- [README.md](README.md) - Application overview
