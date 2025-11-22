**Project Context \& Architecture**

- We are building Azure infrastructure with IaC principles, currently using Azure CLI. 
- It emphasizes the Azure Well-Architected Framework pillars and layered infrastructure design.
- It is intended to use Azure Container Apps for all the services/microservices.
- The infrastructure needs to be designed for multitenancy. 
- We will be deploying each client application/microservices on the same infrastructure, hence each client will be tenant on this infrastructure and depicted as tenantName.

**Mutitenancy Requirement**

- We need to have a common infrastructure for all the tenants that we will onboard in phases(atleast design for 4 Tenants)
- As a part of common infrastructure there needs to have one VNET
- The common infrastructure will have multiple tenants (atleast design for 4 Tenants)
- We want to create multiple Azure Container App Environment for each tenant with tenantName as variable
- Each of the azure container app environment needs to be created in their respective subnets within the same VNET(Common Infrastructure)
- Each of the subnet for azure container app environment should have capacity of atleast 150 IPs 
- Each of the azure container app environment should be internal-only container app environments 
- The VNET will have shared Application Gateway that routes traffic to multiple Container Apps Environments, 
- Each container app environment will potentially hosting multiple applications(container apps)
- Each tenant infers to respective container app environment and is refered as tenantName
- All the container app environments(which will host multiple container apps) needs to be protected behind a single entry point through application gateway with proper SSL/TLS termination.
- Each Container App Environment for a tenantName will have its respective domain 
- The domain will eventually be configured in the routes of the container app envireonment(tenantName)
- Hence the application gateway needs to support multiple domains to route to respective Azure Container App Environment based on the domain name in the url
- A domain will look like nbrly-dev.astrapia.io or bloom-dev.astrapia.io where astrapi.io is a DNS Zone(delegated to Azure DNS), nbrly or bloom are tenantName.
- Each tenantName need to have its own PostGre Database
- astrapi.io has a wild card certificate as *.astrapia.io which will be used for respective domains for tenants such as nbrly-dev.astrapia.io or bloom-dev.astrapia.io

**Layout and Sequence of Scripts Expectation**

I should have the base common infrastructure first
- First Create the base common infrastructure such as VNET, Application Gateway,ResourceGroup, KeyVault, ACR etc.
- Then Create resources for each of the tenantName such as subnet for Azure Container App Environment, User Managed Identity etc

**Suggestions**

- Create the scripts for the infrastructure for 2 tenantName nbrly and bloom
- Make provision for 5 total number of tenantNames (need not have to create all, just 2 tenantName should be good to start with)
- create the scripts for tenantName specific resources in their respective folders in iac-cli/scripts for example iac-cli/scripts for common infrastructure, and for tenantName as nbrly it should be in iac-cli/scripts/nbrly
- The environment variables and parameters should be in the respective folders under config directory for example config/ for common infrastructure resources, config/nbrly for tenantName as nbrly
- Always create documentation md in docs folder of the project. Dont clutter documentation in the other folders
- The VNET design needs to accomodate, subnets for atleast 5 tenants, application gateway,database, azure container app environment, Bastion etc.

**Security Standards**

Comprehensive security guidance aligned with Azure best practices, covering:
- Identity and access management with managed identities and least privilege​
- Network security with NSGs, Azure Firewall, and JIT VM access​
- Data protection with encryption at rest/in transit using Key Vault​
- Compliance with Azure Policy and Azure Security Center

# Security Focused Enhancements

- Identity & Access
    - Use user-assigned managed identity for ACR image pull (no registry username/password in code)
    - Managed identity has only AcrPull role scoped to ACR resource
    - Key Vault uses RBAC or access policy granting only required secret get permissions to the identity
    - Azure Pipelines uses Service Connection (no long-lived secrets)
- Network
    - Container Apps Environment integrated into a subnet (VNet integration)
    - ACR and Key Vault protected by Private Endpoint or firewall rules (restrict to required subnet/service)
    - Ingress is internal-only by default; external ingress requires TLS and domain validation
- Secrets
    - All application secrets stored in Key Vault and referenced by name only
    - No plaintext secrets in scripts, repo, or pipeline logs
    - Secret rotation procedure documented
- Certificates / TLS
    - External ingress uses TLS (Azure-managed or Key Vault-stored cert)
    - Private certificates stored in Key Vault and not committed
- Logging & Monitoring
    - Diagnostics configured to Log Analytics
    - Alerts for failed image pulls, high restart count, high CPU/memory, suspicious outbound traffic
- Image & Runtime Security
    - Image scanned in CI; policy defined for severity threshold
    - Non-root user in container image
    - Resource requests/limits defined
    - Defender for Cloud / runtime protection enabled
- Governance & Operational
    - Tags and ownership metadata added
    - Role assignments limited to resource-group or resource scope as needed
    - Resource locks applied where appropriate for production
    
**References**

Use #fetch to retrieve any additional context or information needed to complete the task from https://learn.microsoft.com/en-us/azure/container-apps/overview and https://learn.microsoft.com/en-us/azure. Always ensure the latest best practices are followed. Further links which will be helpful are as follows:
- #fetch https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom?tabs=bash&pivots=azure-cli
- #fetch https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway?tabs=default-domain
- #fetch https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes
- #fetch https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing-custom-domain

Also use Github Copilot for Azure to design and plan the infrastructure as code, ensuring all security best practices are adhered to.
