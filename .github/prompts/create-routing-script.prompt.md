**Create or update Routing Scripts for Container Apps**

- script should take following inputs:
  1. environment (dev, stage, prod)
  2. tenant name nbrly, bloom). Resolve to actual container app env names for example nbrly-dev-cae, bloom-dev-cae
  3. container app name (e.g., nbapp1, bmapp2). Resolve to actual container app name for example nbrly-dev-nbapp1, bloom-dev-bmapp2
  4. root path as input (e.g., /app1, /app2)
- create the routing yaml from the template file located at manifests/routing/cae-routing-template.yaml
- the name of the route should be same as container app env name for example nbrly-dev-cae, bloom-dev-cae which will be used as parameter to --http-route-config-name while creating the route using azure cli in the script 
- the generated routing yaml should be saved to manifests/.generated/routing/{tenant}-{containerappenv}-routing.yaml for example nbrly-dev-cae-routing.yaml, bloom-dev-cae-routing.yaml
- while adding more container apps under a tenant the script should append the new route to the existing routing yaml file for that tenant container app env.
- finally the script should create or update the route using azure cli command az containerapp env http

