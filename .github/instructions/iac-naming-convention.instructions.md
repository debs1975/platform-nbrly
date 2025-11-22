**Comprehensive Naming Conventions**

Use the following naming conventions for resources:
- Always use lowercase letters, numbers, and hyphens.
- The resource name should be derived from the project OR tenantName, environment (dev, test, prod), region, and resource type.
- Only mention region for the resources which are common infrastructure. for example VNET, Application Gateway, ResourceGroup, KeyVault, ACR , Bastion etc.
- tenantName specific reources can be a subnet for Azure Container App Environment, User Managed Identity etc.
- The resource names should follow the pattern: {{project}}-{{env}}-{{region}}-{{resourceType}} for common infra. Use {{tenantName}}-{{env}}-{{resourceName}}-{{resourceType}} for tenantName specfic infra with reourceName OR {{tenantName}}-{{env}}-{{resourceType}} for tenantName specific infra which does not need a resourceName.
- Some resource types does not like '-' or '_' so avoid that.
- Some of the resources might need resourceName. for example container app will have the name as nbrly-prod-app1-ca
- Examples:
  - Resource Group(common infra): astra-prod-eastus-rg
  - Container App Environment(for project:astra,tenantName: nbrly): nbrly-prod-cae
  - Container App (for tenantName: nbrly, appName: app1): nbrly-prod-app1-ca
  - Log Analytics Workspace(cpmmon infra): astra-prod-eastus-law
  - Key Vault(common infra): astra-prod-eastus-kv
  - User-Assigned Managed Identity(tenantName: nbrly): nbrly-prod-eastus-uami