    **General Role and Context**

    You a python developer with expertise in fast api who understands cloud infrastructure with deep expertise in Azure, secure scripting with Azure CLI, and Azure Pipelines. Always follow Azure security best practices (least privilege, managed identities, Key Vault for secrets, private networking, TLS, logging/monitoring). 

    **Analyse the Infra Architecture**

    - analyse the files azure-ca-appgtwy-detail-design.instructions.md
    - analyse the file deployment-guide.md
    - analyse the file azure-ca-appgtwy-imp-plan.md

    **Analyse the application under sample-app folder**

    - scan through the sample-app folder to understand how application is deployed earlier when application gateway was not used.

    **Please reference the following instruction files when working on this project:

    - Architecture: `.github/instructions/azure-ca-appgtwy-detail-design.instructions.md`
    - Deployment: `.github/instructions/deployment-guide.md`
    - Implementation Plan: `.github/instructions/azure-ca-appgtwy-imp-plan.md`
    - Naming Conventions: `.github/instructions/iac-naming-convention.instructions.md`
    
    **New application requirement**
    
    - create a folder as app-gtwy-apps

    - create the scripts to 
        - create 2 python apps(fast api) as nbapp1 and nbapp2 in the folder app-gtway-apps/nbrly.
        - root url for nbapp1 and nbapp2 in the fastapi code should be /app1 and /app2 respectively
        - create 2 python apps(fast api) as bmapp1 and bmapp2 in the folder app-gtway-apps/bloom.
        - root url for bmapp1 and bmapp2 in the fastapi code should be /app1 and /app2 respectively
    - expected network flow should be as below:
        - domain based routing at application gateway
            - For The DNS should resolve to the application gateway both for https://nbrly-dev.astrapia.io/app1 and https://bloom-dev.astrapia.io/app1
            - container env routing for container app env(tenantName): nbrly as per the respective domain nbrly-dev.astrapia.io
            - container env routing for container app env(tenantName): bloom as per the respective domain bloom-dev.astrapia.io
        - for URL: https://nbrly-dev.astrapia.io/app1 (and for https://nbrly-dev.astrapia.io/app2)
            - The DNS should resolve to the application gateway
            - The application gateway should route the request to tenantName: nbrly container app environment
            - The tenantName: nbrly container app env should resolve it to container app hosting nbapp1 ( this should be implemented in the route of the container app env.)
        - for URL: https://bloom-dev.astrapia.io/app1 (and for https://bloom-dev.astrapia.io/app2)
            - The DNS should resolve to the application gateway
            - The application gateway should route the request to tenantName: bloom container app environment
            - The tenantName: bloom container app env should resolve it to container app hosting bmapp1 ( this should be done at the route of the container app env.)
        
    - create the scripts to 
        - docker build and push to acr for nbapp1 and nbapp2 
        - docker build and push to acr for bmapp1 and bmapp2 
        - nbapp1 and nbapp2 to be deployed in container app env(tenantName): nbrly.
        - bmapp1 and bmapp2 to be deployed in container app env(tenantName): bloom.
    - create the scripts to configure application gateway for path based routing as below:
        - for tenant nbrly
            - URL path based routing for /nbapp1/* to nbapp1 container app
            - URL path based routing for /nbapp2/* to nbapp2 container app
        - for tenant bloom
            - URL path based routing for /bmapp1/* to bmapp1 container app
            - URL path based routing for /bmapp2/* to bmapp2 container app
    - Ensure all naming conventions for resources, images, and container apps
    - Deployment of container apps should happen through yaml files using azure cli commands in the scripts.
    - Generate container app deployment yaml template and the script to generate deployment yaml files dynamically for each container app as per the above requirement.
    - Generate relavant routes.yaml files for container apps deployment as per the above requirement.
    - follow the naming convention as mentioned in iac-naming-convention.instructions.md
    - Fetch and review the following Azure documentation for reference:
        - https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway?tabs=default-domain
        - https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing-custom-domain
        - https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing

