#!/bin/bash
#
# Wrapper script to discover AppDynamics Account IDs using credentials from SSM
# This fetches AppD credentials from AWS SSM and then runs the discovery script
#
# Usage:
#   ./scripts/utils/discover_with_ssm.sh              # Discover only
#   ./scripts/utils/discover_with_ssm.sh --save-to-ssm  # Discover and save to SSM
#

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
SSM_PREFIX="/pepsico"

echo "========================================="
echo "Loading AppDynamics credentials from SSM"
echo "========================================="
echo ""

# Fetch credentials from SSM
echo "Fetching from AWS SSM Parameter Store..."
echo "Region: $AWS_REGION"
echo "Prefix: $SSM_PREFIX"
echo ""

export APPD_CONTROLLERS=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/CONTROLLER" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export APPD_ACCOUNTS=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/ACCOUNT" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export APPD_CLIENT_IDS=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/CLIENT_ID" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export APPD_CLIENT_SECRETS=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/CLIENT_SECRET" \
    --with-decryption \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

# Validate credentials were retrieved
if [ -z "$APPD_CONTROLLERS" ] || [ -z "$APPD_ACCOUNTS" ] || [ -z "$APPD_CLIENT_IDS" ] || [ -z "$APPD_CLIENT_SECRETS" ]; then
    echo "❌ Error: Failed to retrieve AppDynamics credentials from SSM"
    echo ""
    echo "Expected SSM parameters:"
    echo "  ${SSM_PREFIX}/appdynamics/CONTROLLER"
    echo "  ${SSM_PREFIX}/appdynamics/ACCOUNT"
    echo "  ${SSM_PREFIX}/appdynamics/CLIENT_ID"
    echo "  ${SSM_PREFIX}/appdynamics/CLIENT_SECRET"
    echo ""
    echo "Check:"
    echo "  1. SSM parameters exist in region $AWS_REGION"
    echo "  2. AWS credentials are configured (aws configure)"
    echo "  3. IAM permissions include ssm:GetParameter"
    exit 1
fi

echo "✅ Credentials retrieved successfully"
echo "   Controllers: $APPD_CONTROLLERS"
echo "   Accounts: $APPD_ACCOUNTS"
echo ""

# Run the discovery script with any arguments passed to this wrapper
echo "========================================="
echo "Running Account ID Discovery"
echo "========================================="
echo ""

python3 "${SCRIPT_DIR}/discover_appd_account_ids.py" "$@"
