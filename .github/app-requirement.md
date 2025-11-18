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
    - create 2 python apps(fast api) as nbapp1 and nbapp2 in app-gtway-apps/nbrly.
    - root url should be /nbapp1 and /nbapp2 respectively
    - create 2 python apps(fast api) as bmapp1 and bmapp2 in app-gtway-apps/bloom.
    - root url should be /bmapp1 and /bmapp2 respectively
- create the scripts to 
    - docker build and push to acr for nbapp1 and nbapp2 
    - docker build and push to acr for bmapp1 and bmapp2 
    - nbapp1 and nbapp2 to be deployed in container app env: nbrly.
    - bmapp1 and bmapp2 to be deployed in container app env: bloom.
    - container env routing for container app env: nbrly as per the respective domain (example nbrly-dev.astrapia.io)
    - container env routing for container app env: nbrly as per the respective domain (example bloom-dev.astrapia.io)
- follow the naming convention as mentioned in azure-ca-appgtwy.md