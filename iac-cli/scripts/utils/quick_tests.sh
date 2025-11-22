
export ENVIRONMENT="nbrly-dev-eastus-cae"
export RESOURCE_GROUP="nbrly-dev-eastus-rg"

# get the IP address of your Container Apps environment.
az containerapp env show \ 
--name $ENVIRONMENT \
--resource-group $RESOURCE_GROUP \
--query "properties.staticIp"

# Get the domain verification code.
az containerapp env show \
-n $ENVIRONMENT \
-g $RESOURCE_GROUP \
-o tsv \
--query "properties.customeDomainVerificationId"
