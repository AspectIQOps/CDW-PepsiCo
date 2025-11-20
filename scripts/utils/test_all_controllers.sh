#!/bin/bash
#
# Test AppDynamics Licensing API v1 for ALL Controllers
# This script tests each controller sequentially to verify permissions
#
# Usage:
#   ./scripts/utils/test_all_controllers.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
SSM_PREFIX="/pepsico"

echo ""
echo "======================================================================"
echo "  AppDynamics Licensing API v1 - Multi-Controller Test"
echo "======================================================================"
echo ""

# ======================================================================
# STEP 1: Load Credentials from SSM
# ======================================================================

echo "----------------------------------------------------------------------"
echo "Loading AppDynamics Credentials from AWS SSM"
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
    exit 1
fi

echo -e "${GREEN}✅ Credentials loaded successfully${NC}"
echo ""

# Parse arrays
IFS=',' read -ra CONTROLLER_ARRAY <<< "$APPD_CONTROLLERS"
IFS=',' read -ra ACCOUNT_ARRAY <<< "$APPD_ACCOUNTS"
IFS=',' read -ra CLIENT_ID_ARRAY <<< "$APPD_CLIENT_IDS"
IFS=',' read -ra CLIENT_SECRET_ARRAY <<< "$APPD_CLIENT_SECRETS"
IFS=',' read -ra ACCOUNT_ID_ARRAY <<< "$APPD_ACCOUNT_IDS"

# Trim whitespace
for i in "${!CONTROLLER_ARRAY[@]}"; do
    CONTROLLER_ARRAY[$i]=$(echo "${CONTROLLER_ARRAY[$i]}" | xargs)
    ACCOUNT_ARRAY[$i]=$(echo "${ACCOUNT_ARRAY[$i]}" | xargs)
    CLIENT_ID_ARRAY[$i]=$(echo "${CLIENT_ID_ARRAY[$i]}" | xargs)
    CLIENT_SECRET_ARRAY[$i]=$(echo "${CLIENT_SECRET_ARRAY[$i]}" | xargs)
    ACCOUNT_ID_ARRAY[$i]=$(echo "${ACCOUNT_ID_ARRAY[$i]}" | xargs)
done

CONTROLLER_COUNT=${#CONTROLLER_ARRAY[@]}
echo "Found ${CONTROLLER_COUNT} controllers to test:"
for i in "${!CONTROLLER_ARRAY[@]}"; do
    echo "  $((i+1)). ${CONTROLLER_ARRAY[$i]} (Account: ${ACCOUNT_ARRAY[$i]}, ID: ${ACCOUNT_ID_ARRAY[$i]})"
done
echo ""

# Function to test a single controller
test_controller() {
    local CONTROLLER=$1
    local ACCOUNT=$2
    local CLIENT_ID=$3
    local CLIENT_SECRET=$4
    local ACCOUNT_ID=$5
    local INDEX=$6

    echo ""
    echo "======================================================================"
    echo -e "${CYAN}TESTING CONTROLLER ${INDEX}/${CONTROLLER_COUNT}${NC}"
    echo "======================================================================"
    echo ""
    echo "Controller:  $CONTROLLER"
    echo "Account:     $ACCOUNT"
    echo "Account ID:  $ACCOUNT_ID"
    echo ""

    # Get OAuth Token
    echo "Step 1: Getting OAuth token..."
    AUTH_URL="https://${CONTROLLER}/controller/api/oauth/access_token"

    TOKEN_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
      "$AUTH_URL" \
      -d "grant_type=client_credentials" \
      -d "client_id=${CLIENT_ID}@${ACCOUNT}" \
      -d "client_secret=${CLIENT_SECRET}")

    HTTP_STATUS=$(echo "$TOKEN_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$TOKEN_RESPONSE" | sed '/HTTP_STATUS/d')

    if [ "$HTTP_STATUS" != "200" ]; then
        echo -e "${RED}❌ OAuth failed (HTTP $HTTP_STATUS)${NC}"
        echo "Response: $BODY"
        return 1
    fi

    ACCESS_TOKEN=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)

    if [ -z "$ACCESS_TOKEN" ]; then
        echo -e "${RED}❌ Failed to parse access token${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ OAuth token obtained${NC}"

    # Calculate date range (last 7 days)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        DATE_FROM=$(date -u -v-7d +"%Y-%m-%dT%H:%M:%SZ")
        DATE_TO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    else
        DATE_FROM=$(date -u -d '7 days ago' +"%Y-%m-%dT%H:%M:%SZ")
        DATE_TO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    fi

    # Test Account-Level Usage API
    echo ""
    echo "Step 2: Testing Account-Level Usage API..."
    API_URL="https://${CONTROLLER}/controller/licensing/v1/usage/account/${ACCOUNT_ID}"

    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "${API_URL}?dateFrom=${DATE_FROM}&dateTo=${DATE_TO}&granularityMinutes=1440" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json")

    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

    echo "  Endpoint: /controller/licensing/v1/usage/account/${ACCOUNT_ID}"
    echo "  Status: $HTTP_STATUS"

    case $HTTP_STATUS in
        200)
            echo -e "  Result: ${GREEN}✅ SUCCESS${NC}"
            PACKAGES=$(echo "$BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('packages', [])))" 2>/dev/null || echo "0")
            echo "  Packages: $PACKAGES"
            TEST1_RESULT="PASS"
            ;;
        403)
            echo -e "  Result: ${RED}❌ PERMISSION DENIED${NC}"
            ERROR_MSG=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('errorMessage', 'Unknown error'))" 2>/dev/null || echo "$BODY")
            echo "  Error: $ERROR_MSG"
            TEST1_RESULT="FAIL_PERMISSION"
            ;;
        404)
            echo -e "  Result: ${RED}❌ NOT FOUND${NC}"
            TEST1_RESULT="FAIL_NOT_FOUND"
            ;;
        *)
            echo -e "  Result: ${RED}❌ FAILED${NC}"
            echo "  Response: ${BODY:0:200}"
            TEST1_RESULT="FAIL_OTHER"
            ;;
    esac

    # Get application IDs
    echo ""
    echo "Step 3: Fetching application IDs..."
    APPS_URL="https://${CONTROLLER}/controller/rest/applications"

    APP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "${APPS_URL}?output=JSON" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")

    HTTP_STATUS=$(echo "$APP_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$APP_RESPONSE" | sed '/HTTP_STATUS/d')

    if [ "$HTTP_STATUS" = "200" ]; then
        APP_COUNT=$(echo "$BODY" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        echo -e "  Result: ${GREEN}✅ Found $APP_COUNT applications${NC}"

        APP_IDS=$(echo "$BODY" | python3 -c "
import sys, json
apps = json.load(sys.stdin)
ids = [str(app['id']) for app in apps if 'id' in app][:5]
print(','.join(ids))
" 2>/dev/null || echo "")
    else
        echo -e "  Result: ${RED}❌ Failed to fetch applications${NC}"
        APP_IDS=""
    fi

    # Test Grouped Usage API
    echo ""
    echo "Step 4: Testing Grouped Usage API..."

    if [ -z "$APP_IDS" ]; then
        echo -e "  Result: ${YELLOW}⚠️  SKIPPED (no app IDs)${NC}"
        TEST2_RESULT="SKIP"
    else
        # Build query string
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

        RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
          "${API_URL}?${QUERY_STRING}" \
          -H "Authorization: Bearer ${ACCESS_TOKEN}" \
          -H "Content-Type: application/json")

        HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
        BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

        echo "  Endpoint: /controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id"
        echo "  Status: $HTTP_STATUS"

        case $HTTP_STATUS in
            200)
                echo -e "  Result: ${GREEN}✅ SUCCESS${NC}"
                TEST2_RESULT="PASS"
                ;;
            403)
                echo -e "  Result: ${RED}❌ PERMISSION DENIED${NC}"
                ERROR_MSG=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('errorMessage', 'Unknown error'))" 2>/dev/null || echo "$BODY")
                echo "  Error: $ERROR_MSG"
                TEST2_RESULT="FAIL_PERMISSION"
                ;;
            404)
                echo -e "  Result: ${RED}❌ NOT FOUND${NC}"
                TEST2_RESULT="FAIL_NOT_FOUND"
                ;;
            *)
                echo -e "  Result: ${RED}❌ FAILED${NC}"
                TEST2_RESULT="FAIL_OTHER"
                ;;
        esac
    fi

    # Return results
    echo ""
    echo -e "${CYAN}Controller ${INDEX} Summary:${NC}"
    echo "  Account-Level API: $TEST1_RESULT"
    echo "  Grouped Usage API: $TEST2_RESULT"

    # Store results globally
    RESULTS_TEST1+=("$TEST1_RESULT")
    RESULTS_TEST2+=("$TEST2_RESULT")
}

# ======================================================================
# Test All Controllers
# ======================================================================

# Initialize result arrays
RESULTS_TEST1=()
RESULTS_TEST2=()

# Test each controller
for i in "${!CONTROLLER_ARRAY[@]}"; do
    test_controller \
        "${CONTROLLER_ARRAY[$i]}" \
        "${ACCOUNT_ARRAY[$i]}" \
        "${CLIENT_ID_ARRAY[$i]}" \
        "${CLIENT_SECRET_ARRAY[$i]}" \
        "${ACCOUNT_ID_ARRAY[$i]}" \
        "$((i+1))"
done

# ======================================================================
# Overall Summary
# ======================================================================

echo ""
echo "======================================================================"
echo "  OVERALL SUMMARY - ALL CONTROLLERS"
echo "======================================================================"
echo ""

TOTAL_PASS_TEST1=0
TOTAL_PASS_TEST2=0
TOTAL_FAIL_PERMISSION_TEST1=0
TOTAL_FAIL_PERMISSION_TEST2=0

for i in "${!CONTROLLER_ARRAY[@]}"; do
    echo -e "${CYAN}Controller $((i+1)): ${CONTROLLER_ARRAY[$i]}${NC}"
    echo "  Account-Level API: ${RESULTS_TEST1[$i]}"
    echo "  Grouped Usage API: ${RESULTS_TEST2[$i]}"
    echo ""

    # Count results
    [[ "${RESULTS_TEST1[$i]}" == "PASS" ]] && ((TOTAL_PASS_TEST1++)) || true
    [[ "${RESULTS_TEST2[$i]}" == "PASS" ]] && ((TOTAL_PASS_TEST2++)) || true
    [[ "${RESULTS_TEST1[$i]}" == "FAIL_PERMISSION" ]] && ((TOTAL_FAIL_PERMISSION_TEST1++)) || true
    [[ "${RESULTS_TEST2[$i]}" == "FAIL_PERMISSION" ]] && ((TOTAL_FAIL_PERMISSION_TEST2++)) || true
done

echo "======================================================================"
echo ""

if [ $TOTAL_PASS_TEST1 -eq $CONTROLLER_COUNT ] && [ $TOTAL_PASS_TEST2 -eq $CONTROLLER_COUNT ]; then
    echo -e "${GREEN}🎉 ALL CONTROLLERS PASSED ALL TESTS!${NC}"
    echo ""
    echo "Next Steps:"
    echo "  1. Run the ETL pipeline to test end-to-end integration"
    echo "  2. Implement grouped-usage API for per-application license data"
    exit 0
elif [ $TOTAL_FAIL_PERMISSION_TEST1 -gt 0 ] || [ $TOTAL_FAIL_PERMISSION_TEST2 -gt 0 ]; then
    echo -e "${RED}❌ PERMISSION ISSUES DETECTED${NC}"
    echo ""
    echo "Controllers with permission issues:"
    echo "  Account-Level API: $TOTAL_FAIL_PERMISSION_TEST1 / $CONTROLLER_COUNT"
    echo "  Grouped Usage API: $TOTAL_FAIL_PERMISSION_TEST2 / $CONTROLLER_COUNT"
    echo ""
    echo "This indicates the OAuth clients need licensing permissions."
    echo ""
    echo "How to Fix:"
    echo "  1. Log into each AppDynamics Controller UI"
    echo "  2. Navigate to: Settings → Administration → API Clients"
    echo "  3. For each OAuth client, assign 'License Admin' role"
    echo "  4. Save and wait 1-2 minutes for permissions to propagate"
    echo "  5. Re-run this test script"
    echo ""
    echo "Detailed Guide: docs/LICENSING_API_MANUAL_TEST_GUIDE.md"
    exit 1
else
    echo -e "${YELLOW}⚠️  MIXED RESULTS${NC}"
    echo ""
    echo "Some tests passed, some failed. Review the output above."
    echo ""
    echo "Passed Tests:"
    echo "  Account-Level API: $TOTAL_PASS_TEST1 / $CONTROLLER_COUNT"
    echo "  Grouped Usage API: $TOTAL_PASS_TEST2 / $CONTROLLER_COUNT"
    exit 2
fi
