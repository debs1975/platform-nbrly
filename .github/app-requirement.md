**Analyse the Infra Architecture**

- analyse the files azure-ca-appgtwy-detail-design.md
- analyse the file azure-ca-appgtwy.md
- analyse the file deployment-guide.md
- analyse the file azure-ca-appgtwy-imp-plan.md

**Analyse the application under sample-app**

- scan through the directory to understand how application is deployed earlier

**New application requirement**
create a folder as app-gtway-apps

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
          - The tenantName: nbrly container app env should resolve it to container app hosting nbapp1 ( this should be done at the route of the container app env.)
    - for URL: https://bloom-dev.astrapia.io/app1 (and for https://bloom-dev.astrapia.io/app2)
          - The DNS should resolve to the application gateway
          - The application gateway should route the request to tenantName: bloom container app environment
          - The tenantName: bloom container app env should resolve it to container app hosting bmapp1 ( this should be done at the route of the container app env.)
    
- create the scripts to 
    - docker build and push to acr for nbapp1 and nbapp2 
    - docker build and push to acr for bmapp1 and bmapp2 
    - nbapp1 and nbapp2 to be deployed in container app env(tenantName): nbrly.
    - bmapp1 and bmapp2 to be deployed in container app env(tenantName): bloom.
    
- follow the naming convention as mentioned in azure-ca-appgtwy.md
- #fetch https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway?tabs=default-domain
- #fetch https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing-custom-domain
- #fetch https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing
