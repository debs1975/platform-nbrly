I want to configure the topology for 
- For bloom as container app env (refered as tenant)
    - from internet(bloom-dev.astrapia.io/app1)—> DNS—> app gateway—>azure container app env for bloom(bloom-dev-cae) —>container app1(ca-bloom-bmapp1-dev).
    - from internet(bloom-dev.astrapia.io/app2)—> DNS—> app gateway—>azure container app env for bloom(bloom-dev-cae) —>container app2 (ca-bloom-bmapp2-dev).
- For nbrly as container app env (refered as tenant)
    - from internet(nbrly-dev.astrapia.io/app1)—> DNS—> app gateway—>azure container app env for nbrly (nbrly-dev-cae) —>container app1(ca-nbrly-nbapp1-dev).
    - from internet(nbrly-dev.astrapia.io/app2)—> DNS—> app gateway—>azure container app env for nbrly(nbrly-dev-cae) —>container app2 (ca-nbrly-nbapp2-dev).
- bluemeadow-33a9e9ab.eastus.azurecontainerapps.io is the defaultDomain i see for the container app environment
- 10.100.11.197 is the static ip of bloom-dev-cae
- https://ca-bloom-bmapp1-dev.internal.bluemeadow-33a9e9ab.eastus.azurecontainerapps.io is the url i see for ca-bloom-bmapp1-dev
- https://ca-bloom-bmapp2-dev.internal.bluemeadow-33a9e9ab.eastus.azurecontainerapps.io is the url for ca-bloom-bmapp2-dev

bloom-dev-cae
ca-bloom-bmapp1-dev
ca-bloom-bmapp2-dev


I want to configure the topology for 
- For bloom as container app env (refered as tenant)
    - from internet(bloom-dev.astrapia.io/app1)—> DNS—> app gateway—>azure container app env for bloom (bloom-dev-cae) —>container app1(ca-bloom-bmapp1-dev).
    - from internet(bloom-dev.astrapia.io/app2)—> DNS—> app gateway—>azure container app env for bloom(bloom-dev-cae) —>container app2 (ca-bloom-bmapp2-dev).
    - application gateway should route the traffice coming from host header bloom-dev.astrapia.io to bloom-dev-cae as it is
    - bloom-dev-cae should have routes to send the traffic to ca-bloom-bmapp1-dev if the url is bloom-dev.astrapia.io/app1 and send the traffice to ca-bloom-bmapp2-dev if the url is bloom-dev.astrapia.io/app2
    - name of my application gateway is astra-dev-eastus-agw
    - bloom-dev-cae, ca-bloom-bmapp1-dev and ca-bloom-bmapp2-dev are not yet created
    - vnet and subnets are already created. vnet: astra-dev-eastus-vnet, subnet: 
      snet-bloom-dev-cae
    - SSL Certificate: The PFX file for bloom-dev.astrapia.io or a wildcard *.astrapia.io is there is the key vault: astradeveastuskv
- Analyse deeper and first evaluate whether it is a good approach. If so give me detail screen wise steps and respective azure cli commands

10.100.11.184
graycliff-28ad9dd7.eastus.azurecontainerapps.io

https://ca-bloom-bmapp1-dev.graycliff-28ad9dd7.eastus.azurecontainerapps.io
https://ca-bloom-bmapp2-dev.graycliff-28ad9dd7.eastus.azurecontainerapps.io


10.100.10.122
grayfield-aa4022a1.eastus.azurecontainerapps.io

https://ca-nbrly-nbapp1-dev.grayfield-aa4022a1.eastus.azurecontainerapps.io
https://ca-nbrly-nbapp2-dev.grayfield-aa4022a1.eastus.azurecontainerapps.io



I have 4 urls for Azure Container App application:

https://ca-bloom-bmapp1-dev.graycliff-28ad9dd7.eastus.azurecontainerapps.io
https://ca-bloom-bmapp2-dev.graycliff-28ad9dd7.eastus.azurecontainerapps.io
https://ca-nbrly-nbapp1-dev.grayfield-aa4022a1.eastus.azurecontainerapps.io
https://ca-nbrly-nbapp2-dev.grayfield-aa4022a1.eastus.azurecontainerapps.io

In which 
graycliff-28ad9dd7.eastus.azurecontainerapps.io (IP:10.100.10.122) and grayfield-aa4022a1.eastus.azurecontainerapps.io (IP:10.100.10.122) are the container app environments

What should be the private dns zone and corresponding record sets so that
- Any traffic coming on graycliff-28ad9dd7.eastus.azurecontainerapps.io should reach the container app env graycliff-28ad9dd7.eastus.azurecontainerapps.io
- Any traffic coming on grayfield-aa4022a1.eastus.azurecontainerapps.io should reach the container app env grayfield-aa4022a1.eastus.azurecontainerapps.io

I have listeners on Application gateway configured for following:
- bloom-dev.astrapia.io which needs to route traffic to azure container app env graycliff-28ad9dd7.eastus.azurecontainerapps.io
- azure container app env graycliff-28ad9dd7.eastus.azurecontainerapps.io should route traffic of https://bloom-dev.astrapia.io/app1 to the container app ca-bloom-bmapp1-dev
- nbrly-dev.astrapia.io which needs to route traffic to azure container app env grayfield-aa4022a1.eastus.azurecontainerapps.io
- azure container app env grayfield-aa4022a1.eastus.azurecontainerapps.io should route traffic of https://nbrly-dev.astrapia.io/app1 to the container app ca-nbrly-nbapp1-dev

Overall routing needs to look as below:
- For bloom as container app env (refered as tenant)
    - from internet(bloom-dev.astrapia.io/app1)—> DNS—> app gateway—>private dns zone-->azure container app env for bloom(bloom-dev-cae) —>container app1(ca-bloom-bmapp1-dev).
    - from internet(bloom-dev.astrapia.io/app2)—> DNS—> app gateway—>private dns zone-->azure container app env for bloom(bloom-dev-cae) —>container app2 (ca-bloom-bmapp2-dev).
- For nbrly as container app env (refered as tenant)
    - from internet(nbrly-dev.astrapia.io/app1)—> DNS—> app gateway—>private dns zone-->azure container app env for nbrly (nbrly-dev-cae) —>container app1(ca-nbrly-nbapp1-dev).
    - from internet(nbrly-dev.astrapia.io/app2)—> DNS—> app gateway—>private dns zone-->azure container app env for nbrly(nbrly-dev-cae) —>container app2 (ca-nbrly-nbapp2-dev).



az containerapp env http-route-config create \
  --http-route-config-name bloom-dev-cae \
  --resource-group astra-dev-eastus-rg \
  --name bloom-dev-cae \
  --yaml /Users/debashisghosh/Documents/dev/nbrly/app-gtwy-apps/manifests/routing/bloom-dev-cae-routing.yaml \
  --query properties.fqdn

az containerapp env http-route-config delete \
  --http-route-config-name bloom-dev-cae-route \
  --resource-group astra-dev-eastus-rg \
  --name bloom-dev-cae

bloom-dev-cae.graycliff-28ad9dd7.eastus.azurecontainerapps.io

az containerapp env http-route-config create \
  --http-route-config-name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg \
  --name nbrly-dev-cae \
  --yaml /Users/debashisghosh/Documents/dev/nbrly/app-gtwy-apps/manifests/routing/nbrly-dev-cae-routing.yaml \
  --query properties.fqdn

az containerapp env http-route-config delete \
  --http-route-config-name nbrly-dev-cae \
  --resource-group astra-dev-eastus-rg \
  --name nbrly-dev-cae

nbrly-dev-cae.grayfield-aa4022a1.eastus.azurecontainerapps.io