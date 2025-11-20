#!/bin/bash
#
# Interactive Manual Test Script for AppDynamics Licensing API v1
# This script walks you through testing each endpoint step-by-step
#
# Usage:
#   ./scripts/utils/manual_license_api_test.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
SSM_PREFIX="/pepsico"

echo ""
echo "======================================================================"
echo "  AppDynamics Licensing API v1 - Interactive Manual Test"
echo "======================================================================"
echo ""

# Function to pause and wait for user
pause() {
    echo ""
    echo -e "${BLUE}Press ENTER to continue...${NC}"
    read -r
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Success${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed${NC}"
        return 1
    fi
}

# ======================================================================
# STEP 1: Load Credentials from SSM
# ======================================================================

echo "----------------------------------------------------------------------"
echo "STEP 1: Loading AppDynamics Credentials from AWS SSM"
echo "----------------------------------------------------------------------"
echo ""
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

if [ -z "$APPD_CONTROLLERS" ] || [ -z "$APPD_ACCOUNTS" ] || [ -z "$APPD_CLIENT_IDS" ] || [ -z "$APPD_CLIENT_SECRETS" ]; then
    echo -e "${RED}❌ Error: Failed to retrieve credentials from SSM${NC}"
    echo ""
    echo "Expected SSM parameters:"
    echo "  ${SSM_PREFIX}/appdynamics/CONTROLLER"
    echo "  ${SSM_PREFIX}/appdynamics/ACCOUNT"
    echo "  ${SSM_PREFIX}/appdynamics/CLIENT_ID"
    echo "  ${SSM_PREFIX}/appdynamics/CLIENT_SECRET"
    echo "  ${SSM_PREFIX}/appdynamics/ACCOUNT_ID"
    exit 1
fi

echo -e "${GREEN}✅ Credentials loaded successfully${NC}"
echo ""
echo "Controllers: $APPD_CONTROLLERS"
echo "Accounts: $APPD_ACCOUNTS"
echo "Account IDs: $APPD_ACCOUNT_IDS"
echo "Client IDs: ${APPD_CLIENT_IDS:0:20}... (truncated)"

pause

# ======================================================================
# STEP 2: Parse First Controller Values
# ======================================================================

echo ""
echo "----------------------------------------------------------------------"
echo "STEP 2: Parsing First Controller Configuration"
echo "----------------------------------------------------------------------"
echo ""

CONTROLLER=$(echo $APPD_CONTROLLERS | cut -d',' -f1 | xargs)
ACCOUNT=$(echo $APPD_ACCOUNTS | cut -d',' -f1 | xargs)
CLIENT_ID=$(echo $APPD_CLIENT_IDS | cut -d',' -f1 | xargs)
CLIENT_SECRET=$(echo $APPD_CLIENT_SECRETS | cut -d',' -f1 | xargs)
ACCOUNT_ID=$(echo $APPD_ACCOUNT_IDS | cut -d',' -f1 | xargs)

echo "Testing with:"
echo "  Controller:  $CONTROLLER"
echo "  Account:     $ACCOUNT"
echo "  Account ID:  $ACCOUNT_ID"
echo "  Client ID:   ${CLIENT_ID:0:30}..."

pause

# ======================================================================
# STEP 3: Get OAuth Token
# ======================================================================

echo ""
echo "----------------------------------------------------------------------"
echo "STEP 3: Getting OAuth 2.0 Access Token"
echo "----------------------------------------------------------------------"
echo ""

AUTH_URL="https://${CONTROLLER}/controller/api/oauth/access_token"
echo "Calling: $AUTH_URL"
echo "Method: POST"
echo "Grant Type: client_credentials"
echo ""

TOKEN_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  "$AUTH_URL" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}@${ACCOUNT}" \
  -d "client_secret=${CLIENT_SECRET}")

HTTP_STATUS=$(echo "$TOKEN_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$TOKEN_RESPONSE" | sed '/HTTP_STATUS/d')

echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ]; then
    ACCESS_TOKEN=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)

    if [ -n "$ACCESS_TOKEN" ]; then
        echo -e "${GREEN}✅ OAuth token obtained successfully${NC}"
        echo "Token (first 50 chars): ${ACCESS_TOKEN:0:50}..."
        echo "Token length: ${#ACCESS_TOKEN} characters"
    else
        echo -e "${RED}❌ Failed to parse access token from response${NC}"
        echo "Response: $BODY"
        exit 1
    fi
else
    echo -e "${RED}❌ OAuth authentication failed${NC}"
    echo "Response: $BODY"
    exit 1
fi

pause

# ======================================================================
# STEP 4: Test Account-Level Usage API
# ======================================================================

echo ""
echo "----------------------------------------------------------------------"
echo "STEP 4: Testing Account-Level Usage API (v1)"
echo "----------------------------------------------------------------------"
echo ""

# Calculate date range (last 7 days)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    DATE_FROM=$(date -u -v-7d +"%Y-%m-%dT%H:%M:%SZ")
    DATE_TO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
else
    # Linux
    DATE_FROM=$(date -u -d '7 days ago' +"%Y-%m-%dT%H:%M:%SZ")
    DATE_TO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

API_URL="https://${CONTROLLER}/controller/licensing/v1/usage/account/${ACCOUNT_ID}"

echo "Endpoint: /controller/licensing/v1/usage/account/${ACCOUNT_ID}"
echo "Full URL: $API_URL"
echo ""
echo "Query Parameters:"
echo "  dateFrom: $DATE_FROM"
echo "  dateTo: $DATE_TO"
echo "  granularityMinutes: 1440 (daily)"
echo ""
echo "Headers:"
echo "  Authorization: Bearer <token>"
echo "  Content-Type: application/json"
echo ""

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "${API_URL}?dateFrom=${DATE_FROM}&dateTo=${DATE_TO}&granularityMinutes=1440" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "Response Status: $HTTP_STATUS"
echo ""

case $HTTP_STATUS in
    200)
        echo -e "${GREEN}✅ SUCCESS! API returned data${NC}"
        echo ""
        echo "Response (formatted):"
        echo "$BODY" | python3 -m json.tool 2>/dev/null | head -50
        echo ""
        echo "(showing first 50 lines - full response may be longer)"

        # Parse and show summary
        PACKAGES=$(echo "$BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('packages', [])))" 2>/dev/null || echo "0")
        echo ""
        echo "Summary:"
        echo "  Packages: $PACKAGES"
        ;;
    403)
        echo -e "${RED}❌ PERMISSION DENIED (403 Forbidden)${NC}"
        echo ""
        echo "Error Message:"
        echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
        echo ""
        echo -e "${YELLOW}Required Permission: READ LICENSE_USAGE${NC}"
        echo ""
        echo "To fix this, you need to grant licensing permissions to your OAuth client."
        echo "See: docs/LICENSING_API_MANUAL_TEST_GUIDE.md (Step: Granting Licensing API Permissions)"
        ;;
    404)
        echo -e "${RED}❌ NOT FOUND (404)${NC}"
        echo ""
        echo "The endpoint doesn't exist. This could mean:"
        echo "  - Account ID is incorrect"
        echo "  - Licensing API not available on this controller version"
        echo "  - Wrong controller URL"
        ;;
    *)
        echo -e "${RED}❌ FAILED (HTTP $HTTP_STATUS)${NC}"
        echo ""
        echo "Response:"
        echo "$BODY"
        ;;
esac

TEST1_PASSED=$([[ "$HTTP_STATUS" = "200" ]] && echo "true" || echo "false")

pause

# ======================================================================
# STEP 5: Get Application IDs
# ======================================================================

echo ""
echo "----------------------------------------------------------------------"
echo "STEP 5: Fetching Application IDs from Controller"
echo "----------------------------------------------------------------------"
echo ""

APPS_URL="https://${CONTROLLER}/controller/rest/applications"
echo "Endpoint: /controller/rest/applications"
echo "Full URL: ${APPS_URL}?output=JSON"
echo ""

APP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "${APPS_URL}?output=JSON" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}")

HTTP_STATUS=$(echo "$APP_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$APP_RESPONSE" | sed '/HTTP_STATUS/d')

echo "Response Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ]; then
    APP_COUNT=$(echo "$BODY" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Found $APP_COUNT applications${NC}"

    # Extract first 5 app IDs
    APP_IDS=$(echo "$BODY" | python3 -c "
import sys, json
apps = json.load(sys.stdin)
ids = [str(app['id']) for app in apps if 'id' in app][:5]
print(','.join(ids))
" 2>/dev/null || echo "")

    if [ -n "$APP_IDS" ]; then
        echo "Using first 5 app IDs for grouped usage test: $APP_IDS"
    else
        echo -e "${YELLOW}⚠️  No application IDs found - will skip grouped usage test${NC}"
    fi
else
    echo -e "${RED}❌ Failed to fetch applications${NC}"
    echo "Response: $BODY"
    APP_IDS=""
fi

pause

# ======================================================================
# STEP 6: Test Grouped Usage by Application API
# ======================================================================

echo ""
echo "----------------------------------------------------------------------"
echo "STEP 6: Testing Grouped Usage by Application ID API"
echo "----------------------------------------------------------------------"
echo ""

if [ -z "$APP_IDS" ]; then
    echo -e "${YELLOW}⚠️  Skipping - No application IDs available${NC}"
    TEST2_PASSED="skipped"
else
    # Build query string with multiple appId parameters
    IFS=',' read -ra ID_ARRAY <<< "$APP_IDS"
    QUERY_STRING=""
    for id in "${ID_ARRAY[@]}"; do
        if [ -z "$QUERY_STRING" ]; then
            QUERY_STRING="appId=$id"
        else
            QUERY_STRING="${QUERY_STRING}&appId=$id"
        fi
    done

    API_URL="https://${CONTROLLER}/controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id"

    echo "Endpoint: /controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id"
    echo "Full URL: ${API_URL}?${QUERY_STRING}"
    echo ""
    echo "Testing with ${#ID_ARRAY[@]} application IDs"
    echo ""

    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "${API_URL}?${QUERY_STRING}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json")

    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

    echo "Response Status: $HTTP_STATUS"
    echo ""

    case $HTTP_STATUS in
        200)
            echo -e "${GREEN}✅ SUCCESS! API returned per-application data${NC}"
            echo ""
            echo "Response (formatted):"
            echo "$BODY" | python3 -m json.tool 2>/dev/null | head -80
            echo ""
            echo "(showing first 80 lines - full response may be longer)"
            ;;
        403)
            echo -e "${RED}❌ PERMISSION DENIED (403 Forbidden)${NC}"
            echo ""
            echo "Error Message:"
            echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
            echo ""
            echo -e "${YELLOW}Required Permission: READ ACCOUNT_LICENSE${NC}"
            echo ""
            echo "To fix this, you need to grant licensing permissions to your OAuth client."
            echo "See: docs/LICENSING_API_MANUAL_TEST_GUIDE.md (Step: Granting Licensing API Permissions)"
            ;;
        404)
            echo -e "${RED}❌ NOT FOUND (404)${NC}"
            echo ""
            echo "The endpoint doesn't exist. This could mean:"
            echo "  - Grouped-usage API not available on this controller version"
            echo "  - Account ID is incorrect"
            ;;
        *)
            echo -e "${RED}❌ FAILED (HTTP $HTTP_STATUS)${NC}"
            echo ""
            echo "Response:"
            echo "$BODY"
            ;;
    esac

    TEST2_PASSED=$([[ "$HTTP_STATUS" = "200" ]] && echo "true" || echo "false")
fi

pause

# ======================================================================
# SUMMARY
# ======================================================================

echo ""
echo "======================================================================"
echo "  TEST SUMMARY"
echo "======================================================================"
echo ""

if [ "$TEST1_PASSED" = "true" ]; then
    echo -e "Test 1 - Account-Level Usage API: ${GREEN}✅ PASSED${NC}"
else
    echo -e "Test 1 - Account-Level Usage API: ${RED}❌ FAILED${NC}"
fi

if [ "$TEST2_PASSED" = "true" ]; then
    echo -e "Test 2 - Grouped Usage API:       ${GREEN}✅ PASSED${NC}"
elif [ "$TEST2_PASSED" = "skipped" ]; then
    echo -e "Test 2 - Grouped Usage API:       ${YELLOW}⚠️  SKIPPED${NC}"
else
    echo -e "Test 2 - Grouped Usage API:       ${RED}❌ FAILED${NC}"
fi

echo ""
echo "======================================================================"
echo ""

if [ "$TEST1_PASSED" = "true" ] && [ "$TEST2_PASSED" = "true" ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo ""
    echo "The AppDynamics Licensing API v1 is fully accessible."
    echo ""
    echo "Next Steps:"
    echo "  1. Run the ETL pipeline to test end-to-end integration"
    echo "  2. Implement grouped-usage API for per-application license data"
    echo "  3. Validate data in PostgreSQL database"
    exit 0
elif [ "$TEST1_PASSED" = "false" ] || [ "$TEST2_PASSED" = "false" ]; then
    echo -e "${RED}❌ TESTS FAILED${NC}"
    echo ""
    echo "Most Common Issue: PERMISSION DENIED (403)"
    echo ""
    echo "How to Fix:"
    echo "  1. Log into AppDynamics Controller UI"
    echo "  2. Go to: Settings → Administration → API Clients"
    echo "  3. Find your OAuth client (ID: ${CLIENT_ID:0:30}...)"
    echo "  4. Assign one of these roles:"
    echo "     - License Admin (recommended)"
    echo "     - Account Owner (full access)"
    echo "  5. Save and wait 1-2 minutes for permissions to propagate"
    echo "  6. Re-run this test script"
    echo ""
    echo "Detailed Guide: docs/LICENSING_API_MANUAL_TEST_GUIDE.md"
    exit 1
else
    echo -e "${YELLOW}⚠️  PARTIAL SUCCESS${NC}"
    echo ""
    echo "Some tests passed, but not all tests could be completed."
    echo "Review the output above for details."
    exit 2
fi
