 **Analyse the Infra Architecture**

    - analyse the files azure-ca-appgtwy-detail-design.instructions.md
    - analyse the file deployment-guide.md
    - analyse the file azure-ca-appgtwy-imp-plan.md

 **Analyse the application under app-gtwy-apps folder**

    - scan through the sample-app folder to understand how application is deployed earlier when application gateway was not used.

    **Please reference the following instruction files when working on this project:

    - Architecture: `.github/instructions/azure-ca-appgtwy-detail-design.instructions.md`
    - Deployment: `.github/instructions/deployment-guide.md`
    - Implementation Plan: `.github/instructions/azure-ca-appgtwy-imp-plan.md`
    - Naming Conventions: `.github/instructions/iac-naming-convention.instructions.md`

**Expected network flow should be as below:**

    - domain based routing at application gateway
        - The url https://bloom-dev.astrapia.io/app1 should be resolved by Azure DNS (delegated from astrapia.io) to the application gateway public IP
        - The url https://nbrly-dev.astrapia.io/app1 should be resolved by Azure DNS (delegated from astrapia.io) to the application gateway public IP
    - The application gateway should route the request to respective container app environment based on the listener configuration:
        - for listener bloom-dev.astrapia.io → backend pool pointing to bloom-dev-cae.graycliff-28ad9dd7.eastus.azurecontainerapps.io → private DNS zone(graycliff-28ad9dd7.eastus.azurecontainerapps.io) resolves to route of the container app environment bloom-dev-cae as bloom-dev-cae.graycliff-28ad9dd7.eastus.azurecontainerapps.io  → container app hosting bmapp1 i.e. ca-bloom-bmapp1-dev or container app hosting bmapp2 i.e. ca-bloom-bmapp2-dev ( this should be implemented in the route of the container app env.)
        - for listener nbrly-dev.astrapia.io → backend pool pointing to nbrly-dev-cae.grayfield-aa4022a1.eastus.azurecontainerapps.io → private DNS zone(grayfield-aa4022a1.eastus.azurecontainerapps.io) resolves to route of the container app environment nbrly-dev-cae as nbrly-dev-cae.grayfield-aa4022a1.eastus.azurecontainerapps.io  → container app hosting nbapp1 i.e. ca-nbrly-nbapp1-dev or container app hosting nbapp2 i.e. ca-nbrly-nbapp2-dev ( this should be done at the route of the container app env.)
      
**Sequence and structure of the scripts should be as below:**
    - iac-cli is the folder under which iac-cli/scripts is used to create base infrastructure and tenant onboarding
    - app-gtwy-apps is the folder under which container app deployment scripts will be created
    - Scripts under iac-cli/scripts folder should be structured as below:
        1. Create the base infrastructure creation scripts as below:
            - create or update respective parameter files under iac-cli/config folder as per the naming convention mentioned in iac-naming-convention.instructions.md. for example parameters-dev.json for dev environment .
            - create or update respective infra-dev.json under iac-cli/config folder to keep the resource details created as part of infrastructure creation scripts in iac-cli which needs to be referred in the tenant onboarding scripts and app-gtwy-apps scripts later
            - Generate the required parameters in the parameters files as per the naming convention mentioned in iac-naming-convention.instructions.md
            - create the infrastructure creation script to take environment as input parameter to create the required base infrastructure.
            - The required parameters should be fetched from iac-cli/config/parameters-{ENV}.json using helper function get_infra_value in the scripts
            - create resource group if does not exist
            - create vnet with required address space 
            - create subnet for private endpoints (subnet CIDR should have 32 IPs for private endpoints)
            - create subnet for postgresql server ( subnet CIDR should have 32 IPs for postgresql server)
            - create subnet for Bastion host ( subnet CIDR should have 32 IPs for bastion host)
            - create subnet for vmss ( subnet CIDR should have 64 IPs for vmss instances)
            - create subnets for application gateway (subnet CIDR should have enough IPs for application gateway instances) 
            - create container registry and key vault
            - upload the ssl certificate (*.astrapria.io) from iac-cli/cred to key vault
            - create managed identities required for application gateway
            - assign required role assignments to the managed identities created for application gateway to access key vault
            - create application gateway with required public IP, key vault, ssl cert from key vault, frontend IP config, backend pools( empty at this stage), http settings( empty at this stage), listeners( empty at this stage), routing rules( empty at this stage)    
            - create private link for application gateway to the vnet created
           
            
        2. Create separate scripts for tenant onboarding under iac-cli/scripts/tenant folder as below:
            - create or update respective parameter files under iac-cli/config folder as per the naming convention mentioned in iac-naming-convention.instructions.md. for example parameters-dev.json for dev environment .
            - create or update respective infra-dev.json under iac-cli/config folder to keep the resource details created as part of infrastructure creation scripts in iac-cli which needs to be referred in the tenant onboarding scripts and app-gtwy-apps scripts later
            - Generate the required parameters in the parameters files as per the naming convention mentioned in iac-naming-convention.instructions.md
            - create the infrastructure creation script to take environment as input parameter to create the required base infrastructure.
            - The required parameters should be fetched from iac-cli/config/parameters-{ENV}.json using helper function get_infra_value in the scripts
            - create the tenant onboarding script to take tenantName as input parameter to create the respective tenant subnet, container app environment and required private DNS zone and record sets, backend pools, http settings, listeners, routing rules in the application gateway.
            - create the subnet for the tenant container app environment with required address space (subnet CIDR should have 200+ IPs for container app environment)
            - create the user managed identity for the tenant container app environment to access key vault and container registry
            - create the tenant container app environment in the respective subnet created. The container app environment should be internal.
            - create the private DNS zone for the tenant container app environment
            - create the private DNS zone link to link the private DNS zone to the vnet created in step 1
            - create the required record sets in the private DNS zone to point to the route of the container app environment created in this step
               - for example if the tenantName is bloom, the private DNS zone created should be graycliff-28ad9dd7.eastus.azurecontainerapps.io and the record set created in this private DNS zone should be * pointing to the route of the container app environment bloom-dev-cae such as bloom-dev-cae.graycliff-28ad9dd7.eastus.azurecontainerapps.io
            - create the backend pools in the application gateway to point to the route of the container app environment created in this step. For example if the tenantName is bloom, the backend pool created should be bloom-bp pointing to bloom-dev-cae.graycliff-28ad9dd7.eastus.azurecontainerapps.io
            - create the http settings in the application gateway for the tenant container app environment created in this step. For example if the tenantName is bloom, the http settings created should be bloom-http-settings with required port, protocol, health probe configuration etc.
            - create the listener in the application gateway for the tenant container app environment created in this step
               - for example for the tenantName bloom and environment dev, the listener created should be bloom-dev.astrapia.io
            - create the basic routing rules in the application gateway for the tenant container app environment created in this step
               - for example for the tenantName bloom and environment dev, the routing rule created should be bloom-rl with required backend pool as bloom-bp, http settings as bloom-http-settings, listener as bloom-dev.astrapia.io etc.
            
    - For app-gtwy-apps: 
        - create or update respective parameter files under app-gtwy-apps/config folder as per the naming convention mentioned in iac-naming-convention.instructions.md. for example parameters-dev.json for dev environment .
        - create or update respective infra-dev.json under app-gtwy-apps/config folder to keep the resource details created as part of infrastructure creation scripts in app-gtwy-apps 
        - Generate the required parameters in the parameters files as per the naming convention mentioned in iac-naming-convention.instructions.md
        - Copy over any parameters required for container app environment creation from iac-cli/config/infra-dev.json and iac-cli/config/parameters-dev.json to app-gtwy-apps/config/infra-dev.json and app-gtwy-apps/config/parameters-dev.json respectively.
        - Create the apps
            1. Create python fast api apps under apps folder as below (script not required, just the steps):
                - create python fast api app as per the app name input parameter with root path as /app1. For example if app name is bmapp1, the root path should be /app1
                - create python fast api app for the app name bmapp1 and nbapp1 with health endpoint at /app1/health 
                - create the dockerfile for each the apps to containerize the apps
            2. Docker build and push to ACR
                - create the script to take environment, app name and tag as input parameter to docker build and push the respective app to the container registry created as part of infrastructure creation in iac-cli
        - create the scripts to deploy the container apps in respective container app environment as below:
            1. create the script to take environment and app name as input parameter to create the required resources
                - bmapp1 needs to be deployed in container app env(tenantName): bloom and hence the container app env name is bloom-dev-cae.
                - nbapp1 needs to be deployed in container app env(tenantName): nbrly and hence the container app env name is nbrly-dev-cae
                - the container apps ingress traffic should be configured as Limited to Vnet
                - create the scripts create routing rule conatiner app environment for path based routing as below:
                        - for tenant nbrly, URL path based routing for /app1 to nbapp1 container app
                        - for tenant bloom, URL path based routing for /app1 to bmapp1 container app  
                        - Generate relavant <container-app-env>-routes.yaml files under app-gtwy-apps/manifests/routing folder for the above path based routing configuration
                            - for example bloom-dev-cae-routes.yaml for tenant bloom and nbrly-dev-cae-routes.yaml for tenant nbrly
                        - the name of the route needs to be <container-app-env>, for example bloom-dev-cae for tenant bloom and nbrly-dev-cae for tenant nbrly
                - create the scripts to deploy the container app environment routing configuration as below:
                    - the script should take environment and tenantName as input parameter to deploy the respective container app environment routing configuration using the respective <container-app-env>-routes.yaml file created in the previous step
                    
**Config files and Parameters file:**
    - follow the naming convention as mentioned in iac-naming-convention.instructions.md
    - create config folder under iac-cli and app-gtwy-apps 
    - create infra-dev.json under iac-cli/config to keep the resource details created as part of infrastructure creation scripts in iac-cli
    - create parameters file under config folder of iac-cli and app-gtwy-apps respectively to keep the parameters files as per the environment(dev,prod etc)
    - infra parameters file under iac-cli/config/parameters-dev.json should have all the infra parameters required for infrastructure creation 
    - the required infra parameters should be fetched from infra-dev.json using helper function get_infra_value in the scripts
    - copy the infra parameters required for container app environment creation from infra-dev.json to app-gtwy-apps/config/infra-dev.json as part of the container app environment onboarding script in iac-cli
    - create app specific parameters file under app-gtwy-apps/config/parameters-dev.json to keep the app specific parameters required for container app deployment and application gateway configuration
    - the app specific parameters should be fetched from app-gtwy-apps/config/parameters-dev.json using helper function

**Reverse Engineer and Update:**
    - the complete setup has been implemented as per the above requirement under resource group: astra-dev-eastus-rg in Azure portal.
    - reverse engineer the complete setup and update the scripts, config files, parameters files, yaml files etc under iac-cli and app-gtwy-apps folder as per the above requirement. 