# Helper Scripts

This directory contains reusable helper scripts for Container App deployment operations.

## Scripts

### setup-keyvault-secrets.sh

Creates placeholder secrets in Azure Key Vault for Container Apps with database dependencies.

**Purpose:**
- Automatically creates required KeyVault secrets for both NBRLY and BLOOM tenants
- Creates placeholder PostgreSQL connection strings
- Skips secrets that already exist (idempotent)

**Usage:**
```bash
./helpers/setup-keyvault-secrets.sh
```

**What it creates:**
- `nbrly-psql-connection-string`: PostgreSQL connection string for NBRLY tenant
- `bloom-psql-connection-string`: PostgreSQL connection string for BLOOM tenant

**Notes:**
- Placeholder values use dummy credentials and server names
- Update with actual connection strings once PostgreSQL servers are provisioned
- Automatically called by YAML deployment scripts (08, 09) if secrets are missing

**Updating secrets:**
```bash
az keyvault secret set \
  --vault-name <keyvault-name> \
  --name <secret-name> \
  --value <actual-connection-string>
```

### generate-manifests.sh

Generates Container App YAML manifests from templates.

**Usage:**
```bash
./helpers/generate-manifests.sh [tenant]
```

**Parameters:**
- `tenant`: Optional. Specify `nbrly`, `bloom`, or `all` (default: `all`)

**Examples:**
```bash
# Generate only NBRLY manifests
./helpers/generate-manifests.sh nbrly

# Generate only BLOOM manifests
./helpers/generate-manifests.sh bloom

# Generate all manifests
./helpers/generate-manifests.sh all
```

### config-loader.sh

Loads configuration from JSON files.

**Functions:**
- `get_infra_value()`: Get values from infra-dev.json
- `get_app_config()`: Get application configuration values
- `get_tenant_value()`: Get tenant-specific configuration values

### configure-routing.sh

Configures HTTP routing with custom domains for Container App Environments.

**Purpose:**
- Applies rule-based routing configuration with custom domains
- Supports both NBRLY and BLOOM tenants
- Enables path-based routing to different container apps
- **Note**: SSL/TLS termination is handled by Application Gateway, so CAE uses HTTP only

**Usage:**
```bash
./helpers/configure-routing.sh [nbrly|bloom|all]
```

**Parameters:**
- `tenant`: Specify `nbrly`, `bloom`, or `all` (default: `all`)

**Examples:**
```bash
# Configure routing for NBRLY only
./helpers/configure-routing.sh nbrly

# Configure routing for BLOOM only
./helpers/configure-routing.sh bloom

# Configure routing for both tenants
./helpers/configure-routing.sh all
```

**What it does:**
1. Generates routing YAML from templates in `manifests/routing/`
2. Applies routing configuration with custom domains (HTTP only):
   - NBRLY: `nbrly-dev.astrapia.io`
   - BLOOM: `bloom-dev.astrapia.io`
3. Configures path-based routing:
   - `/app1` → nbapp1/bmapp1
   - `/app2` → nbapp2/bmapp2

**Requirements:**
- Container apps must be deployed before configuring routing
- DNS A records should point to Application Gateway public IP

**Architecture Notes:**
- SSL/TLS certificates are managed by Application Gateway, not Container App Environments
- Container App Environments use `bindingType: Disabled` (HTTP only)
- All HTTPS termination happens at the App Gateway layer
- No certificates need to be uploaded to CAEs

**DNS Configuration:**
After running this script, configure DNS A records:
```bash
# Both domains point to Application Gateway public IP
nbrly-dev.astrapia.io  →  20.42.50.96
bloom-dev.astrapia.io  →  20.42.50.96
```

### logging.sh

Centralized logging functions for all scripts.

**Functions:**
- `log()`: Blue informational message with timestamp
- `error()`: Red error message with timestamp
- `success()`: Green success message with timestamp
- `warning()`: Yellow warning message with timestamp

## Integration

The deployment scripts (08, 09) automatically call these helpers:
1. Check for required KeyVault secrets
2. Create placeholders if missing
3. Generate tenant-specific manifests
4. Deploy using YAML

After deployment, run the routing configuration helper:
```bash
./helpers/configure-routing.sh all
```

This ensures a smooth deployment experience without manual secret or routing management.
