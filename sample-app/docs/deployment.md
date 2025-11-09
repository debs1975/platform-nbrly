# Quick Deployment Guide

## YAML-Based Deployment (Recommended)

### Quick Start

```bash
cd sample-app
./scripts/deploy-yaml.sh dev
```

### What Gets Created

```
sample-app/manifests/.generated/
└── containerapp-dev.yaml    # Generated manifest with all variables substituted
```

### Deployment Flow

```
1. Load config          → config/parameters-dev.json
2. Build image          → docker build
3. Push to ACR          → docker push
4. Generate YAML        → sed substitution on template
5. Deploy/Update        → az containerapp create/update --yaml
```

## File Locations

| File | Purpose | Versioned |
|------|---------|-----------|
| `manifests/containerapp.yaml` | Template with {{variables}} | ✅ Yes |
| `manifests/.generated/*.yaml` | Generated manifests | ❌ No (gitignored) |
| `scripts/deploy-yaml.sh` | Deployment script | ✅ Yes |
| `scripts/deploy.sh` | CLI-based deployment | ✅ Yes |

## Environment-Specific Deployments

```bash
# Development
./scripts/deploy-yaml.sh dev

# Staging  
./scripts/deploy-yaml.sh staging

# Production
./scripts/deploy-yaml.sh prod
```

## Comparison: YAML vs CLI

| Feature | YAML Deployment | CLI Deployment |
|---------|----------------|----------------|
| **Command** | `deploy-yaml.sh` | `deploy.sh` |
| **Method** | `--yaml manifest.yaml` | `--image --cpu --memory ...` |
| **Version Control** | ✅ Template in Git | ❌ Only script in Git |
| **Configuration Visibility** | ✅ Full config in one file | ❌ Spread across CLI flags |
| **GitOps Ready** | ✅ Yes | ❌ No |
| **Review Changes** | ✅ Easy (diff YAML) | ❌ Hard (diff script) |
| **Declarative** | ✅ Yes | ❌ Imperative |
| **Learning Curve** | Medium | Easy |

## Quick Commands

### Deploy
```bash
./scripts/deploy-yaml.sh dev
```

### View Generated Manifest
```bash
cat manifests/.generated/containerapp-dev.yaml
```

### View Deployed Config
```bash
az containerapp show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --output yaml
```

### Update Only Image (Without Full Redeploy)
```bash
# Option 1: Update manifest and redeploy
./scripts/deploy-yaml.sh dev

# Option 2: Quick image update via CLI
az containerapp update \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --image nbrlydeveastusacr.azurecr.io/sample-api:v2.0
```

### View Logs
```bash
az containerapp logs show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --follow
```

## Customization Points

### 1. Resource Limits
Edit `manifests/containerapp.yaml`:
```yaml
template:
  containers:
    - resources:
        cpu: 1.0        # Change from 0.5
        memory: 2.0Gi   # Change from 1.0Gi
```

### 2. Scaling Rules
Edit `manifests/containerapp.yaml`:
```yaml
template:
  scale:
    minReplicas: 1      # Change from 0 (disable scale-to-zero)
    maxReplicas: 20     # Change from 10
```

### 3. Environment Variables
Edit `manifests/containerapp.yaml`:
```yaml
template:
  containers:
    - env:
        - name: NEW_VAR
          value: "new_value"
```

### 4. Health Probes
Edit `manifests/containerapp.yaml`:
```yaml
template:
  containers:
    - probes:
        - type: liveness
          httpGet:
            path: /app1/health/live
          failureThreshold: 5    # More tolerant
```

## Troubleshooting

### Issue: Variables Not Replaced

**Symptom:** See `{{VARIABLE}}` in generated manifest

**Fix:**
```bash
# Check deploy-yaml.sh includes this variable in sed command
grep "{{VARIABLE}}" scripts/deploy-yaml.sh
```

### Issue: Deployment Fails

**Check:**
```bash
# 1. Infrastructure exists
az containerapp env show --name nbrly-dev-eastus-cae --resource-group nbrly-dev-eastus-rg

# 2. Image exists in ACR
az acr repository show --name nbrlydeveastusacr --repository sample-api

# 3. Managed identity has permissions
az role assignment list \
  --assignee $(az identity show --name nbrly-dev-eastus-uami --resource-group nbrly-dev-eastus-rg --query principalId -o tsv)
```

### Issue: Container Won't Start

**Check logs:**
```bash
az containerapp logs show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --tail 100
```

### Issue: Secrets Not Loading

**Verify:**
```bash
# Key Vault exists
az keyvault show --name nbrlydeveastuskv

# Secrets exist
az keyvault secret list --vault-name nbrlydeveastuskv

# Managed identity has access
az role assignment list \
  --scope $(az keyvault show --name nbrlydeveastuskv --query id -o tsv)
```

## Advanced Usage

### Multi-Region Deployment

Create region-specific manifests:
```bash
# East US
sed -e "s|eastus|eastus|g" \
    manifests/containerapp.yaml > manifests/.generated/containerapp-dev-eastus.yaml

# West US
sed -e "s|eastus|westus|g" \
    manifests/containerapp.yaml > manifests/.generated/containerapp-dev-westus.yaml
```

### Blue-Green Deployment

```bash
# Deploy v2 as new revision
az containerapp revision copy \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --image nbrlydeveastusacr.azurecr.io/sample-api:v2.0

# Split traffic
az containerapp ingress traffic set \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --revision-weight latest=50 previous=50

# Full cutover
az containerapp ingress traffic set \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --revision-weight latest=100
```

### Export Current Config as Template

```bash
# Export current deployment
az containerapp show \
  --name nbrly-dev-eastus-api-ca \
  --resource-group nbrly-dev-eastus-rg \
  --output yaml > current-config.yaml

# Replace specific values with variables
sed -i \
  -e "s|nbrly-dev-eastus-api-ca|{{APP_NAME}}|g" \
  -e "s|nbrlydeveastusacr.azurecr.io/sample-api:.*|{{IMAGE_NAME}}|g" \
  current-config.yaml
```

## Next Steps

1. ✅ Deploy with YAML: `./scripts/deploy-yaml.sh dev`
2. ✅ Verify deployment: Check endpoints in output
3. ✅ Setup monitoring: `./scripts/setup-monitoring.sh dev`
4. ✅ Configure routing (optional): `./scripts/deploy-routing.sh dev`
5. 🔄 Customize template: Edit `manifests/containerapp.yaml`
6. 🔄 Add CI/CD: Integrate into GitHub Actions or Azure DevOps
7. 🔄 Deploy to staging/prod: Test changes across environments

For infrastructure configuration:
- SSL/TLS setup: See `../../docs/ssl-tls-setup.md` and run `../../scripts/06-deploy-ssl.sh`

## Resources

- [Full Documentation](../README.md)
- [Manifest Documentation](manifests.md)
- [Configuration Documentation](configuration.md)
- [HTTP Routing Guide](routing.md)
- [Container Apps YAML Reference](https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec)
