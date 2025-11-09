#!/bin/bash
set -e

# ============================================================================
# Script: deploy.sh
# Purpose: Complete deployment automation script that orchestrates the build,
#          push, and deployment process for containerized applications to 
#          Azure Container Apps
# 
# Description:
#   This is a convenience wrapper script that automates the complete deployment
#   workflow by sequentially calling build-push.sh and deploy-app.sh scripts.
#   It handles Docker image building, pushing to Azure Container Registry,
#   and deploying/updating the container application.
#
# Usage: 
#   ./deploy.sh [environment] [tag] [app]
#
# Parameters:
#   environment  - Target deployment environment (default: 'dev')
#                  Examples: dev, staging, prod
#   tag         - Custom image tag (optional)
#                 If not provided, auto-generated tag will be used
#   app         - Application name (default: 'app')
#                 Used for image naming and container app identification
#
# Examples:
#   ./deploy.sh                           # Deploy 'app' to 'dev' with auto tag
#   ./deploy.sh prod                      # Deploy 'app' to 'prod' with auto tag
#   ./deploy.sh staging v1.2.3           # Deploy 'app' to 'staging' with tag 'v1.2.3'
#   ./deploy.sh dev latest my-service     # Deploy 'my-service' to 'dev' with tag 'latest'
#
# Dependencies:
#   - build-push.sh: Must exist in same directory for building and pushing images
#   - deploy-app.sh: Must exist in same directory for container app deployment
#   - Azure CLI configured with appropriate permissions
#   - Docker installed and configured
#
# Workflow:
#   1. Validates input parameters and sets defaults
#   2. Calls build-push.sh to build Docker image and push to ACR
#   3. Calls deploy-app.sh to deploy/update the container app
#   4. Provides progress feedback and completion status
#
# Exit Codes:
#   0 - Success
#   1 - Error (script fails fast with 'set -e')
#
# Notes:
#   - Script uses 'set -e' for fail-fast behavior
#   - Each app gets its own separate Docker image
#   - Custom tags are propagated to both build and deploy phases
#   - Script provides detailed progress output for monitoring
# ============================================================================

ENVIRONMENT=${1:-dev}
CUSTOM_TAG=${2:-}
APP_NAME=${3:-app}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Complete Deployment Workflow"
echo "=========================================="
echo "Environment: ${ENVIRONMENT}"
echo "Application: ${APP_NAME}"
if [ -n "$CUSTOM_TAG" ]; then
    echo "Custom Tag:  ${CUSTOM_TAG}"
fi
echo ""
echo "This script will:"
echo "  1. Build Docker image (${APP_NAME})"
echo "  2. Push to Azure Container Registry"
echo "  3. Deploy/Update Container App"
echo "=========================================="

# Step 1: Build and push image (separate image per app)
echo ""
echo "=== Step 1/2: Building and Pushing Image ==="
if [ -n "$CUSTOM_TAG" ]; then
    "${SCRIPT_DIR}/build-push.sh" "$ENVIRONMENT" "$CUSTOM_TAG" "$APP_NAME"
else
    "${SCRIPT_DIR}/build-push.sh" "$ENVIRONMENT" "" "$APP_NAME"
fi

# Step 2: Deploy container app
echo ""
echo "=== Step 2/2: Deploying Container App ==="
if [ -n "$CUSTOM_TAG" ]; then
    "${SCRIPT_DIR}/deploy-app.sh" "$ENVIRONMENT" "$CUSTOM_TAG" "$APP_NAME"
else
    "${SCRIPT_DIR}/deploy-app.sh" "$ENVIRONMENT" "" "$APP_NAME"
fi

echo ""
echo "=========================================="
echo "Complete Deployment Finished!"
echo "=========================================="
