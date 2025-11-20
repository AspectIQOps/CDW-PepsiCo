#!/bin/bash
#
# Wrapper script to test AppDynamics Licensing API using credentials from SSM
#
# Usage:
#   ./scripts/utils/test_license_api_with_ssm.sh
#

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
SSM_PREFIX="/pepsico"

echo "========================================="
echo "AppDynamics Licensing API v1 Test"
echo "========================================="
echo ""

# Fetch credentials from SSM
echo "Loading credentials from AWS SSM Parameter Store..."
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

export APPD_ACCOUNT_IDS=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/ACCOUNT_ID" \
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
    echo "  ${SSM_PREFIX}/appdynamics/ACCOUNT_ID"
    exit 1
fi

echo "✅ Credentials retrieved successfully"
echo ""

# Run the test script
python3 "${SCRIPT_DIR}/test_license_api.py"
