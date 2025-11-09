# Container App Monitoring & Alerting

## Overview
This document describes monitoring and alerting configurations for Container Apps deployed from this application. These alerts complement the infrastructure-level monitoring configured in `/scripts/05-deploy-monitoring.sh`.

## Architecture
- **Infrastructure Monitoring**: Configured during infrastructure deployment (ACR, PostgreSQL, Key Vault)
- **Application Monitoring**: Configured during application deployment (Container App metrics, logs, Application Insights)

## Alert Configurations

### 1. High Restart Count Alert
**Trigger**: Container restarts exceed threshold within time window  
**Severity**: 2 (Warning)  
**Purpose**: Detect application crashes or health check failures

**Configuration**:
```bash
az monitor metrics alert create \
    --name "${APP_NAME}-high-restarts" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg Restarts > 5" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when container restarts exceed 5 in 5 minutes" \
    --severity 2
```

**Typical Causes**:
- Application crash on startup (missing dependencies, configuration errors)
- Health probe failures (timeouts, incorrect endpoints)
- Out of memory (OOM) kills
- Unhandled exceptions causing process exit

**Investigation Steps**:
1. Check container logs: `az containerapp logs show --name $APP_NAME -g $RG_NAME --follow`
2. Review recent deployments and configuration changes
3. Check health probe configuration (`/health/ready`, `/health/live`)
4. Verify memory and CPU allocation vs. actual usage
5. Review Application Insights exception tracking

---

### 2. High CPU Usage Alert
**Trigger**: Average CPU usage exceeds 80% of allocated resources  
**Severity**: 3 (Informational)  
**Purpose**: Detect performance bottlenecks and scaling needs

**Configuration**:
```bash
az monitor metrics alert create \
    --name "${APP_NAME}-high-cpu" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg UsageNanoCores > 400000000" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when CPU usage exceeds 80% (0.4 cores of 0.5 allocated)" \
    --severity 3
```

**Note**: Adjust threshold based on allocated CPU:
- 0.25 cores → 200000000 nanocores (80% = 0.2 cores)
- 0.5 cores → 400000000 nanocores (80% = 0.4 cores)
- 1.0 cores → 800000000 nanocores (80% = 0.8 cores)

**Typical Causes**:
- Inefficient code (N+1 queries, blocking operations)
- High request volume without sufficient replicas
- CPU-intensive operations (data processing, image manipulation)
- Insufficient CPU allocation for workload

**Investigation Steps**:
1. Check Application Insights performance metrics
2. Review auto-scaling configuration and replica count
3. Analyze slow requests and database query performance
4. Profile application code for CPU hotspots
5. Consider vertical scaling (increase CPU allocation) or horizontal scaling (more replicas)

---

### 3. High Memory Usage Alert
**Trigger**: Memory usage exceeds 85% of allocated resources  
**Severity**: 2 (Warning)  
**Purpose**: Prevent OOM kills and performance degradation

**Configuration**:
```bash
az monitor metrics alert create \
    --name "${APP_NAME}-high-memory" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg WorkingSetBytes > 912680960" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when memory usage exceeds 85% (870 MB of 1 GB allocated)" \
    --severity 2
```

**Note**: Calculate threshold based on allocated memory:
- 512 MB → 458 MB (85%) = 480247808 bytes
- 1 GB → 870 MB (85%) = 912680960 bytes
- 2 GB → 1.7 GB (85%) = 1825361920 bytes

**Typical Causes**:
- Memory leaks (unreleased objects, unclosed connections)
- Large in-memory data structures
- Insufficient memory allocation for workload
- Caching without size limits

**Investigation Steps**:
1. Monitor memory metrics over time for leak patterns
2. Review application code for connection pooling and resource cleanup
3. Check for large result sets loaded into memory
4. Analyze caching strategies and limits
5. Consider increasing memory allocation or optimizing code

---

### 4. HTTP Request Latency Alert
**Trigger**: 95th percentile response time exceeds threshold  
**Severity**: 3 (Informational)  
**Purpose**: Detect performance degradation affecting user experience

**Configuration**:
```bash
az monitor metrics alert create \
    --name "${APP_NAME}-high-latency" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg HttpResponseTime > 2000" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when HTTP response time exceeds 2 seconds" \
    --severity 3
```

**Typical Causes**:
- Database query performance issues
- External API timeouts or slow responses
- Insufficient resources (CPU throttling, memory pressure)
- Network latency or DNS resolution delays
- Blocking I/O operations in async code

**Investigation Steps**:
1. Check Application Insights request telemetry and dependencies
2. Analyze slow database queries (PostgreSQL pg_stat_statements)
3. Review external API response times
4. Check container resource utilization
5. Profile code for synchronous operations in async handlers

---

### 5. HTTP Error Rate Alert
**Trigger**: 5xx error rate exceeds threshold  
**Severity**: 1 (Critical)  
**Purpose**: Detect application errors and service degradation

**Configuration**:
```bash
az monitor metrics alert create \
    --name "${APP_NAME}-high-errors" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "total Http5xxCount > 10" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when 5xx errors exceed 10 in 5 minutes" \
    --severity 1
```

**Typical Causes**:
- Unhandled exceptions in application code
- Database connection failures
- Dependency service failures (Key Vault, external APIs)
- Configuration errors (missing environment variables)
- Resource exhaustion (connection pool, file handles)

**Investigation Steps**:
1. Check Application Insights exceptions and failed requests
2. Review container logs for stack traces
3. Verify database connectivity and health
4. Check Key Vault access and secret references
5. Validate environment configuration

---

### 6. Scale-to-Zero Recovery Alert
**Trigger**: Container App has been at 0 replicas for extended period  
**Severity**: 3 (Informational)  
**Purpose**: Monitor cost optimization and cold start impacts

**Configuration**:
```bash
az monitor metrics alert create \
    --name "${APP_NAME}-zero-replicas" \
    --resource-group "$RG_NAME" \
    --scopes "$CONTAINER_APP_ID" \
    --condition "avg Replicas == 0" \
    --window-size 30m \
    --evaluation-frequency 5m \
    --action "$ACTION_GROUP_ID" \
    --description "Alert when app has been scaled to zero for 30 minutes" \
    --severity 3
```

**Purpose**: 
- Track scale-to-zero patterns for cost analysis
- Identify low-traffic periods
- Plan for cold start mitigation if needed

**Investigation Steps**:
1. Review traffic patterns and usage analytics
2. Evaluate if minimum replicas should be configured
3. Assess cold start impact on user experience
4. Consider cost vs. performance trade-offs

---

## Application Insights Integration

### Automatic Telemetry
When Application Insights is configured, the Container App automatically collects:
- Request telemetry (duration, status code, URL)
- Dependency telemetry (database, HTTP calls)
- Exception telemetry (unhandled exceptions)
- Custom events and metrics
- Log messages (stdout/stderr)

### Configuration
Set the Application Insights connection string as an environment variable:

```bash
# Get connection string from infrastructure
APPINSIGHTS_CONN_STRING=$(az monitor app-insights component show \
    --app "${PROJECT_NAME}-${ENV}-eastus-ai" \
    --resource-group "$RG_NAME" \
    --query connectionString -o tsv)

# Update Container App
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG_NAME" \
    --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CONN_STRING"
```

### Custom Instrumentation (Python FastAPI)
```python
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# Configure Application Insights
configure_azure_monitor(
    connection_string=os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
)

# Instrument FastAPI
app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
```

### Custom Metrics Example
```python
from opentelemetry import metrics

meter = metrics.get_meter(__name__)
request_counter = meter.create_counter(
    name="api.requests",
    description="Number of API requests",
    unit="1"
)

@app.get("/api/users")
async def get_users():
    request_counter.add(1, {"endpoint": "/api/users"})
    # ... endpoint logic
```

---

## Log Analytics Queries

### Recent Restarts
```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "nbrly-dev-eastus-api-ca"
| where Log_s contains "Container restarted" or Log_s contains "exit code"
| project TimeGenerated, Log_s
| order by TimeGenerated desc
| take 50
```

### Error Log Pattern
```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "nbrly-dev-eastus-api-ca"
| where Log_s contains "ERROR" or Log_s contains "Exception"
| summarize ErrorCount = count() by bin(TimeGenerated, 5m), ErrorPattern = extract(@"ERROR: (.+)", 1, Log_s)
| order by TimeGenerated desc
```

### Resource Usage Over Time
```kusto
ContainerAppSystemLogs_CL
| where ContainerAppName_s == "nbrly-dev-eastus-api-ca"
| summarize 
    AvgCPU = avg(CpuUsageNanoCores_d),
    AvgMemory = avg(MemoryWorkingSetBytes_d),
    ReplicaCount = max(ReplicaCount_d)
  by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

### Request Performance
```kusto
requests
| where cloud_RoleName == "nbrly-dev-eastus-api-ca"
| summarize 
    RequestCount = count(),
    AvgDuration = avg(duration),
    P95Duration = percentile(duration, 95),
    ErrorRate = countif(success == false) * 100.0 / count()
  by bin(timestamp, 5m), name
| order by timestamp desc
```

---

## Alert Deployment Script

Use `scripts/setup-monitoring.sh` to deploy all Container App-specific alerts:

```bash
cd sample-app
./scripts/setup-monitoring.sh dev
```

This script:
1. Retrieves Container App and Action Group IDs
2. Creates all metric-based alerts
3. Configures Application Insights integration
4. Validates alert rules

---

## Alert Management

### List Active Alerts
```bash
az monitor metrics alert list \
    --resource-group "$RG_NAME" \
    --query "[?contains(name, '${APP_NAME}')].{Name:name, Enabled:enabled, Severity:severity}" \
    --output table
```

### Disable Alert Temporarily
```bash
az monitor metrics alert update \
    --name "${APP_NAME}-high-restarts" \
    --resource-group "$RG_NAME" \
    --enabled false
```

### Update Alert Threshold
```bash
az monitor metrics alert update \
    --name "${APP_NAME}-high-cpu" \
    --resource-group "$RG_NAME" \
    --condition "avg UsageNanoCores > 600000000"  # Increase to 60%
```

---

## Best Practices

### Alert Design
1. **Actionable**: Every alert should have clear investigation steps
2. **Appropriate Severity**: Critical (1) for service down, Warning (2) for degradation, Info (3) for trends
3. **Avoid Alert Fatigue**: Tune thresholds based on actual workload patterns
4. **Context-Rich**: Include resource details and suggested actions in descriptions

### Monitoring Strategy
1. **Golden Signals**: Monitor latency, traffic, errors, and saturation
2. **Gradual Rollout**: Start with conservative thresholds, adjust based on data
3. **Regular Review**: Weekly review of alert frequency and false positives
4. **Documentation**: Keep runbooks updated with investigation procedures

### Cost Optimization
1. **Consolidate Alerts**: Use multi-resource alerts where possible
2. **Appropriate Frequency**: Balance responsiveness with cost (1m vs 5m evaluation)
3. **Log Sampling**: Use Application Insights sampling for high-volume apps
4. **Data Retention**: Archive old logs to cheaper storage tiers

---

## Related Documentation
- [Infrastructure Monitoring](/docs/azure-infrastructure-design-dev.md) - Platform-level monitoring
- [Application README](../README.md) - Application overview and deployment
- [Azure Monitor Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/)
- [Container Apps Metrics](https://learn.microsoft.com/en-us/azure/container-apps/observability)
