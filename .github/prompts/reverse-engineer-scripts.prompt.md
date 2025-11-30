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
   
    1. in the folder iac-cli create/update the scripts to create the base infrastructure including VNET and Subnet,application gateway, key vault, container registry
    2. after step 1, 
        - create the separate script to onboard each tenant container app environment ( and not container app) with required private DNS zone and record sets, backend pools, http settings, listeners, routing rules in the application gateway. 
        - The container app environment onboarding script should be parameterized to take tenantName as input parameter to create the respective container app environment along with private DNS zone and record sets, backend pools, http settings, listeners, routing rules in the application gateway. 
        - The container app environment is internal amd is associated with the respective subnet created in step 1.
    3. in the folder app-gtwy-apps create the scripts to 
        - There are already 2 python apps(fast api) as nbapp1 and nbapp2 in the folder app-gtway-apps/nbrly.
        - root url for nbapp1 and nbapp2 in the fastapi code should be /app1 and /app2 respectively
        - There are already 2 python apps(fast api) as bmapp1 and bmapp2 in the folder app-gtway-apps/bloom.
        - root url for bmapp1 and bmapp2 in the fastapi code should be /app1 and /app2 respectively
        - create the scripts to 
            - docker build and push to acr for nbapp1 and nbapp2. These already exists, hence no need to create again. 
            - docker build and push to acr for bmapp1 and bmapp2. These already exists, hence no need to create again.
            - nbapp1 and nbapp2 to be deployed in container app env(tenantName): nbrly and hence the container app env name is nbrly-dev-cae.
            - bmapp1 and bmapp2 to be deployed in container app env(tenantName): bloom and hence the container app env name is bloom-dev-cae.
            - the container apps ingress traffic should be configured as Limited to Vnet
            - create the scripts to configure application gateway for path based routing as below:
                - for tenant nbrly
                    - URL path based routing for /app1 to nbapp1 container app
                    - URL path based routing for /app2 to nbapp2 container app
                - for tenant bloom
                    - URL path based routing for /app1 to bmapp1 container app
                    - URL path based routing for /app2 to bmapp2 container app
                - Generate relavant <container-app-env>-routes.yaml files and names of the routes as <container-app-env>.<domain of the container app environment> for container apps deployment as per the above requirement. for example: bloom-dev-cae-routes.yaml and nbrly-dev-cae-routes.yaml, route name as bloom-dev-cae and nbrly-dev-cae respectively.

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