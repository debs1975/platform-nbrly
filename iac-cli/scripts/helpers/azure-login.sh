#!/bin/bash

# This script handles logging into Azure.
# It first attempts to use a Service Principal from a credentials file.
# If the file is not found or the login fails, it falls back to interactive browser login.

show_login_details() {
  echo "----------------------------------------"
  echo "Azure Login Details:"
  az account show --query "{
    Account: user.name,
    Type: user.type,
    Subscription: name,
    SubscriptionId: id,
    TenantId: tenantId
  }" -o table
  echo "----------------------------------------"
}

# Function to log in to Azure
azure_login() {
  # Accept optional environment parameter, default to dev
  local ENV="${1:-dev}"

  # Determine the path to the credentials file relative to this script's location.
  local HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  CRED_FILE_PATH="${HELPER_DIR}/../../creds/azure-credentials-${ENV}.cred"

  # Attempt Service Principal login if the credentials file exists
  if [ -f "$CRED_FILE_PATH" ]; then
    echo "Found credentials file. Attempting login with Service Principal..."

    # Load credentials from JSON file
    AZURE_SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$CRED_FILE_PATH")
    AZURE_TENANT_ID=$(jq -r '.tenantId' "$CRED_FILE_PATH")
    AZURE_CLIENT_ID=$(jq -r '.clientId' "$CRED_FILE_PATH")
    AZURE_CLIENT_SECRET=$(jq -r '.clientSecret' "$CRED_FILE_PATH")

    # Export for use in other scripts if needed
    export AZURE_SUBSCRIPTION_ID
    export AZURE_TENANT_ID

    az login --service-principal \
      -u "$AZURE_CLIENT_ID" \
      -p "$AZURE_CLIENT_SECRET" \
      --tenant "$AZURE_TENANT_ID" > /dev/null

    if [ $? -eq 0 ]; then
      az account set --subscription "$AZURE_SUBSCRIPTION_ID" > /dev/null
      echo "Successfully logged in with Service Principal."
      show_login_details
      return 0 # Success
    else
      echo "Service Principal login failed. Falling back to interactive login."
    fi
  else
    echo "Service Principal credentials not found. Falling back to interactive login."
  fi

  # Fallback to interactive login
  echo "A browser window will open for authentication..."
  az login > /dev/null
  if [ $? -ne 0 ]; then
    echo "Interactive Azure login failed. Please try again."
    exit 1
  fi
  
  echo "Successfully logged in interactively."
  show_login_details
  echo "Ensure this is the correct subscription for the deployment."
}

# Export the function so it can be used by sourcing scripts
export -f azure_login

# Main execution (only runs when script is executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  azure_login
  exit $?
fi
