# Sample App Configuration

This directory contains environment-specific configuration for the sample Container App. These configs are separate from the infrastructure configuration in `/config` and focus on application-level settings.

## Configuration Files

- `app-config-dev.json` - Development environment settings
- `app-config-staging.json` - Staging environment settings
- `app-config-prod.json` - Production environment settings

## Configuration Structure

```json
{
  "containerApp": {
    "nameSuffix": "api-ca",
    "image": {
      "repository": "sample-api",
      "tag": "latest"
    },
    "resources": {
      "cpu": "0.5",
      "memory": "1.0Gi"
    },
    "scaling": {
      "minReplicas": 0,
      "maxReplicas": 10,
      "rules": {
        "http": {
          "concurrentRequests": 10
        }
      }
    },
    "healthProbes": {
      "liveness": {
        "initialDelaySeconds": 10,
        "periodSeconds": 30,
        "timeoutSeconds": 5,
        "failureThreshold": 3
      },
      "readiness": {
        "initialDelaySeconds": 5,
        "periodSeconds": 10,
        "timeoutSeconds": 3,
        "failureThreshold": 3
      },
      "startup": {
        "initialDelaySeconds": 0,
        "periodSeconds": 5,
        "timeoutSeconds": 3,
        "failureThreshold": 30
      }
    },
    "container": {
      "port": 8000
    }
  },
  "environment": {
    "LOG_LEVEL": "INFO",
    "ENVIRONMENT": "dev"
  },
  "tags": {
    "Application": "sample-api",
    "Component": "backend-api"
  }
}
```

## Configuration Settings

### Container App Settings

#### `nameSuffix`
Resource name suffix for the Container App (e.g., `api-ca` results in `{project}-{env}-{region}-api-ca`)

#### `image.repository`
Container image repository name in ACR

#### `image.tag`
Container image tag to deploy:
- **dev**: `latest` - Always use the latest build
- **staging**: `latest` - Use latest for testing
- **prod**: `stable` - Use stable/tagged releases

#### `resources.cpu`
vCPU allocation per container:
- **dev**: `0.5` - Minimal resources for cost savings
- **staging**: `1.0` - Moderate resources for realistic testing
- **prod**: `2.0` - Production-grade resources

#### `resources.memory`
Memory allocation per container:
- **dev**: `1.0Gi` - Basic memory allocation
- **staging**: `2.0Gi` - Adequate for load testing
- **prod**: `4.0Gi` - Production capacity

### Scaling Configuration

#### `minReplicas`
Minimum number of running replicas:
- **dev**: `0` - Scale to zero when idle (cost optimization)
- **staging**: `1` - Keep 1 replica warm
- **prod**: `2` - High availability (minimum 2 replicas)

#### `maxReplicas`
Maximum number of replicas for auto-scaling:
- **dev**: `10` - Limited scaling for development
- **staging**: `20` - Moderate scaling for testing
- **prod**: `50` - High scaling capacity for production traffic

#### `rules.http.concurrentRequests`
Number of concurrent requests per replica before scaling out:
- **dev**: `10` - Aggressive scaling for testing
- **staging**: `20` - Balanced scaling
- **prod**: `30` - Conservative scaling (better stability)

### Health Probe Settings

#### Liveness Probe
Restarts container if health check fails:
- `initialDelaySeconds`: Wait before first check (10-15s)
- `periodSeconds`: How often to check (30s)
- `failureThreshold`: Failures before restart (3)

#### Readiness Probe
Stops sending traffic if health check fails:
- `initialDelaySeconds`: Wait before first check (5s)
- `periodSeconds`: How often to check (10s)
- `failureThreshold`: Failures before removing from load balancer (3)

#### Startup Probe
For slow-starting applications:
- `failureThreshold`: Maximum attempts (30 × 5s = 150s max startup time)

### Environment Variables

#### `LOG_LEVEL`
Application logging verbosity:
- **dev**: `INFO` - Detailed logging for debugging
- **staging**: `INFO` - Standard logging
- **prod**: `WARNING` - Minimal logging (production)

#### `ENVIRONMENT`
Environment identifier for application logic

### Resource Tags

Tags applied to Azure resources for organization and cost tracking:
- `Application`: Application identifier
- `Component`: Component type (backend-api)
- `CriticalityLevel`: Business criticality (prod only)

## Environment-Specific Differences

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| CPU | 0.5 | 1.0 | 2.0 |
| Memory | 1.0Gi | 2.0Gi | 4.0Gi |
| Min Replicas | 0 (scale-to-zero) | 1 | 2 (HA) |
| Max Replicas | 10 | 20 | 50 |
| Image Tag | latest | latest | stable |
| Log Level | INFO | INFO | WARNING |
| Startup Timeout | 150s | 150s | 150s |

## Usage

### In Deployment Scripts

Scripts automatically load the appropriate config based on environment:

```bash
# Load app config
APP_CONFIG_FILE="./config/app-config-${ENVIRONMENT}.json"

# Extract values
APP_NAME_SUFFIX=$(jq -r '.containerApp.nameSuffix' "$APP_CONFIG_FILE")
CONTAINER_CPU=$(jq -r '.containerApp.resources.cpu' "$APP_CONFIG_FILE")
MIN_REPLICAS=$(jq -r '.containerApp.scaling.minReplicas' "$APP_CONFIG_FILE")
```

### In YAML Templates

Variables from config are substituted into YAML manifests:

```yaml
resources:
  cpu: {{CONTAINER_CPU}}
  memory: {{CONTAINER_MEMORY}}

scale:
  minReplicas: {{MIN_REPLICAS}}
  maxReplicas: {{MAX_REPLICAS}}
```

## Customization

To customize settings for your application:

1. **Modify resource allocations** based on your app's requirements
2. **Adjust scaling rules** based on expected traffic patterns
3. **Tune health probe timings** based on startup and response characteristics
4. **Update environment variables** for application-specific configuration
5. **Add new settings** following the existing JSON structure

## Validation

Validate JSON syntax before deploying:

```bash
jq empty app-config-dev.json
jq empty app-config-staging.json
jq empty app-config-prod.json
```

## Best Practices

1. **Keep configs in sync**: Ensure all environments have the same structure
2. **Test changes in dev first**: Validate configuration changes in dev before promoting
3. **Document custom settings**: Add comments to this README when adding custom fields
4. **Version control**: Always commit config changes with descriptive messages
5. **Secure secrets**: Never put secrets in config files - use Key Vault references
6. **Resource right-sizing**: Regularly review and adjust resource allocations based on actual usage

## Related Documentation

- Infrastructure config: `/config/parameters-{env}.json`
- Deployment guide: `deployment.md`
- Monitoring setup: `../scripts/setup-monitoring.sh`
- YAML manifest: `manifests.md`
