#!/bin/bash
#
# Quick AppDynamics Licensing API Test - Hardcoded Credentials
# No prompts, no AWS - just run and get results
# Perfect for live calls with client to verify permissions
#
# Usage: bash test_licensing_api_quick.sh
#

set -e

# HARDCODED CREDENTIALS (edit if needed)
APPD_CONTROLLERS="pepsi-test.saas.appdynamics.com,pepsico-nonprod.saas.appdynamics.com,pepsicoeu-test.saas.appdynamics.com"
APPD_ACCOUNTS="pepsi-test,pepsico-nonprod,pepsicoeu-test"
APPD_CLIENT_IDS="License Dashboard Client Key,License Dashboard Client Key,License Dashboard Client Key"
APPD_CLIENT_SECRETS="6b0ad3f5-6290-46c2-acdc-ea9fed258d01,a51dcf72-2a9c-4282-b5d8-12f3ce99a4a7,cb1a7df3-476f-473e-8ff0-1b66e9c4acc8"
APPD_ACCOUNT_IDS="193,259,55"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "======================================================================"
echo "  AppDynamics Licensing API v1 - Quick Test"
echo "======================================================================"
echo ""
echo "This script tests the AppDynamics Licensing API v1 endpoints to verify"
echo "that OAuth clients have the required permissions."
echo ""
echo "Testing endpoints:"
echo "  1. /controller/licensing/v1/usage/account/{accountId}"
echo "  2. /controller/licensing/v1/account/{accountId}/grouped-usage/application/by-id"
echo ""
echo "Required permissions:"
echo "  - READ LICENSE_USAGE"
echo "  - READ ACCOUNT_LICENSE"
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

echo "======================================================================"
echo "  Configuration"
echo "======================================================================"
echo ""
echo "Found ${CONTROLLER_COUNT} controllers:"
for i in "${!CONTROLLER_ARRAY[@]}"; do
    echo "  $((i+1)). ${CONTROLLER_ARRAY[$i]}"
    echo "     Account: ${ACCOUNT_ARRAY[$i]}"
    echo "     Account ID: ${ACCOUNT_ID_ARRAY[$i]}"
    echo "     Client ID: ${CLIENT_ID_ARRAY[$i]:0:30}..."
    echo ""
done
echo "======================================================================"
echo "  Starting Tests"
echo "======================================================================"
echo ""

# Helper function for JSON parsing
json_get() {
    if command -v python3 &> /dev/null; then
        echo "$1" | python3 -c "import sys, json; print(json.load(sys.stdin).get('$2', ''))" 2>/dev/null || echo ""
    elif command -v python &> /dev/null; then
        echo "$1" | python -c "import sys, json; print json.load(sys.stdin).get('$2', '')" 2>/dev/null || echo ""
    else
        echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"\([^"]*\)".*/\1/' | head -1
    fi
}

# Date helpers
get_date_7_days_ago() {
    if command -v python3 &> /dev/null; then
        python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow() - timedelta(days=7)).strftime('%Y-%m-%dT%H:%M:%SZ'))"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        date -u -v-7d +"%Y-%m-%dT%H:%M:%SZ"
    else
        date -u -d '7 days ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT00:00:00Z"
    fi
}

get_date_now() {
    if command -v python3 &> /dev/null; then
        python3 -c "from datetime import datetime; print(datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'))"
    else
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# Test function
test_controller() {
    local CONTROLLER=$1
    local ACCOUNT=$2
    local CLIENT_ID=$3
    local CLIENT_SECRET=$4
    local ACCOUNT_ID=$5
    local INDEX=$6

    echo ""
    echo -e "${CYAN}======================================================================"
    echo -e "  Controller $INDEX of $CONTROLLER_COUNT: $CONTROLLER"
    echo -e "======================================================================${NC}"
    echo ""
    echo "  Account: $ACCOUNT"
    echo "  Account ID: $ACCOUNT_ID"
    echo ""

    # Get OAuth Token
    echo "  [Step 1/4] Authenticating with OAuth 2.0..."
    echo "    Endpoint: https://${CONTROLLER}/controller/api/oauth/access_token"
    echo "    Client: ${CLIENT_ID}@${ACCOUNT}"

    TOKEN_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
      "https://${CONTROLLER}/controller/api/oauth/access_token" \
      -d "grant_type=client_credentials" \
      -d "client_id=${CLIENT_ID}@${ACCOUNT}" \
      -d "client_secret=${CLIENT_SECRET}")

    HTTP_STATUS=$(echo "$TOKEN_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$TOKEN_RESPONSE" | sed '/HTTP_STATUS/d')

    if [ "$HTTP_STATUS" != "200" ]; then
        echo -e "    Status: ${RED}❌ FAILED (HTTP $HTTP_STATUS)${NC}"
        echo "    Error: Unable to authenticate"
        echo ""
        return
    fi

    ACCESS_TOKEN=$(json_get "$BODY" "access_token")
    if [ -z "$ACCESS_TOKEN" ]; then
        echo -e "    Status: ${RED}❌ FAILED (no token in response)${NC}"
        echo ""
        return
    fi

    echo -e "    Status: ${GREEN}✅ SUCCESS${NC}"
    echo "    Token: ${ACCESS_TOKEN:0:20}... (truncated)"
    echo ""

    # Dates
    DATE_FROM=$(get_date_7_days_ago)
    DATE_TO=$(get_date_now)

    # Test 1: Account-Level Usage API
    echo "  [Step 2/4] Testing Account-Level Usage API..."
    echo "    Endpoint: /controller/licensing/v1/usage/account/${ACCOUNT_ID}"
    echo "    Date Range: ${DATE_FROM} to ${DATE_TO}"
    echo "    Granularity: 1440 minutes (daily)"

    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "https://${CONTROLLER}/controller/licensing/v1/usage/account/${ACCOUNT_ID}?dateFrom=${DATE_FROM}&dateTo=${DATE_TO}&granularityMinutes=1440" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json")

    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

    echo "    HTTP Status: $HTTP_STATUS"

    if [ "$HTTP_STATUS" = "200" ]; then
        echo -e "    Result: ${GREEN}✅ PASS${NC}"
        echo "    API returned license usage data successfully"
        TEST1_RESULT="PASS"
    elif [ "$HTTP_STATUS" = "403" ]; then
        echo -e "    Result: ${RED}❌ PERMISSION DENIED${NC}"
        ERROR_MSG=$(json_get "$BODY" "errorMessage")
        echo "    Error: $ERROR_MSG"
        echo "    Fix: Client needs 'READ LICENSE_USAGE' permission"
        TEST1_RESULT="FAIL_PERMISSION"
    else
        echo -e "    Result: ${RED}❌ FAIL${NC}"
        echo "    Unexpected error occurred"
        TEST1_RESULT="FAIL_OTHER"
    fi
    echo ""

    # Get app IDs
    echo "  [Step 3/4] Fetching application IDs..."
    echo "    Endpoint: /controller/rest/applications"

    APP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "https://${CONTROLLER}/controller/rest/applications?output=JSON" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")

    HTTP_STATUS=$(echo "$APP_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$APP_RESPONSE" | sed '/HTTP_STATUS/d')

    echo "    HTTP Status: $HTTP_STATUS"

    if [ "$HTTP_STATUS" = "200" ]; then
        if command -v python3 &> /dev/null; then
            APP_COUNT=$(echo "$BODY" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
            APP_IDS=$(echo "$BODY" | python3 -c "import sys, json; apps = json.load(sys.stdin); print(','.join([str(app['id']) for app in apps if 'id' in app][:5]))" 2>/dev/null || echo "")
        else
            APP_IDS=$(echo "$BODY" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | head -5 | sed 's/.*:\s*//' | tr '\n' ',' | sed 's/,$//')
            APP_COUNT=$(echo "$BODY" | grep -o '"id"' | wc -l | xargs)
        fi
        echo -e "    Result: ${GREEN}✅ Found $APP_COUNT applications${NC}"
        echo "    Using first 5 IDs for grouped usage test: $APP_IDS"
    else
        echo -e "    Result: ${RED}❌ Failed to fetch applications${NC}"
        APP_IDS=""
    fi
    echo ""

    # Test 2: Grouped Usage API
    echo "  [Step 4/4] Testing Grouped Usage by Application API..."
    if [ -z "$APP_IDS" ]; then
        echo -e "    Result: ${YELLOW}⚠️  SKIPPED (no application IDs)${NC}"
        TEST2_RESULT="SKIP"
    else
        IFS=',' read -ra ID_ARRAY <<< "$APP_IDS"
        QUERY_STRING=""
        for id in "${ID_ARRAY[@]}"; do
            [ -z "$QUERY_STRING" ] && QUERY_STRING="appId=$id" || QUERY_STRING="${QUERY_STRING}&appId=$id"
        done

        echo "    Endpoint: /controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id"
        echo "    Testing with ${#ID_ARRAY[@]} application IDs"

        RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
          "https://${CONTROLLER}/controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id?${QUERY_STRING}" \
          -H "Authorization: Bearer ${ACCESS_TOKEN}" \
          -H "Content-Type: application/json")

        HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
        BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

        echo "    HTTP Status: $HTTP_STATUS"

        if [ "$HTTP_STATUS" = "200" ]; then
            echo -e "    Result: ${GREEN}✅ PASS${NC}"
            echo "    API returned per-application license data successfully"
            TEST2_RESULT="PASS"
        elif [ "$HTTP_STATUS" = "403" ]; then
            echo -e "    Result: ${RED}❌ PERMISSION DENIED${NC}"
            ERROR_MSG=$(json_get "$BODY" "errorMessage")
            echo "    Error: $ERROR_MSG"
            echo "    Fix: Client needs 'READ ACCOUNT_LICENSE' permission"
            TEST2_RESULT="FAIL_PERMISSION"
        else
            echo -e "    Result: ${RED}❌ FAIL${NC}"
            echo "    Unexpected error occurred"
            TEST2_RESULT="FAIL_OTHER"
        fi
    fi
    echo ""

    RESULTS_TEST1+=("$TEST1_RESULT")
    RESULTS_TEST2+=("$TEST2_RESULT")
}

# Initialize results
RESULTS_TEST1=()
RESULTS_TEST2=()

# Test all controllers
for i in "${!CONTROLLER_ARRAY[@]}"; do
    test_controller \
        "${CONTROLLER_ARRAY[$i]}" \
        "${ACCOUNT_ARRAY[$i]}" \
        "${CLIENT_ID_ARRAY[$i]}" \
        "${CLIENT_SECRET_ARRAY[$i]}" \
        "${ACCOUNT_ID_ARRAY[$i]}" \
        "$((i+1))"
done

# Summary
echo ""
echo "======================================================================"
echo "  FINAL RESULTS SUMMARY"
echo "======================================================================"
echo ""

TOTAL_PASS_TEST1=0
TOTAL_PASS_TEST2=0
TOTAL_FAIL_PERMISSION_TEST1=0
TOTAL_FAIL_PERMISSION_TEST2=0

for i in "${!CONTROLLER_ARRAY[@]}"; do
    echo -e "${CYAN}Controller $((i+1)): ${CONTROLLER_ARRAY[$i]}${NC}"
    echo "  Account: ${ACCOUNT_ARRAY[$i]} (ID: ${ACCOUNT_ID_ARRAY[$i]})"

    # Usage API result
    if [[ "${RESULTS_TEST1[$i]}" == "PASS" ]]; then
        echo -e "  Account-Level Usage API: ${GREEN}✅ PASS${NC}"
    elif [[ "${RESULTS_TEST1[$i]}" == "FAIL_PERMISSION" ]]; then
        echo -e "  Account-Level Usage API: ${RED}❌ PERMISSION DENIED${NC}"
    else
        echo -e "  Account-Level Usage API: ${RED}❌ ${RESULTS_TEST1[$i]}${NC}"
    fi

    # Grouped API result
    if [[ "${RESULTS_TEST2[$i]}" == "PASS" ]]; then
        echo -e "  Grouped Usage API:       ${GREEN}✅ PASS${NC}"
    elif [[ "${RESULTS_TEST2[$i]}" == "FAIL_PERMISSION" ]]; then
        echo -e "  Grouped Usage API:       ${RED}❌ PERMISSION DENIED${NC}"
    elif [[ "${RESULTS_TEST2[$i]}" == "SKIP" ]]; then
        echo -e "  Grouped Usage API:       ${YELLOW}⚠️  SKIPPED${NC}"
    else
        echo -e "  Grouped Usage API:       ${RED}❌ ${RESULTS_TEST2[$i]}${NC}"
    fi

    echo ""

    [[ "${RESULTS_TEST1[$i]}" == "PASS" ]] && ((TOTAL_PASS_TEST1++)) || true
    [[ "${RESULTS_TEST2[$i]}" == "PASS" ]] && ((TOTAL_PASS_TEST2++)) || true
    [[ "${RESULTS_TEST1[$i]}" == "FAIL_PERMISSION" ]] && ((TOTAL_FAIL_PERMISSION_TEST1++)) || true
    [[ "${RESULTS_TEST2[$i]}" == "FAIL_PERMISSION" ]] && ((TOTAL_FAIL_PERMISSION_TEST2++)) || true
done

echo "======================================================================"
echo ""
echo "Total Controllers Tested: $CONTROLLER_COUNT"
echo ""
echo "Account-Level Usage API:"
echo "  Passed: $TOTAL_PASS_TEST1 / $CONTROLLER_COUNT"
echo "  Failed (Permission): $TOTAL_FAIL_PERMISSION_TEST1 / $CONTROLLER_COUNT"
echo ""
echo "Grouped Usage API:"
echo "  Passed: $TOTAL_PASS_TEST2 / $CONTROLLER_COUNT"
echo "  Failed (Permission): $TOTAL_FAIL_PERMISSION_TEST2 / $CONTROLLER_COUNT"
echo ""
echo "======================================================================"
echo ""

if [ $TOTAL_PASS_TEST1 -eq $CONTROLLER_COUNT ] && [ $TOTAL_PASS_TEST2 -eq $CONTROLLER_COUNT ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo ""
    echo "All controllers have proper licensing API permissions."
    echo "Ready to proceed with ETL integration."
    exit 0
elif [ $TOTAL_FAIL_PERMISSION_TEST1 -gt 0 ] || [ $TOTAL_FAIL_PERMISSION_TEST2 -gt 0 ]; then
    echo -e "${RED}❌ PERMISSION ISSUES DETECTED${NC}"
    echo ""

    # Count unique controllers with issues
    CONTROLLERS_WITH_ISSUES=0
    for i in "${!CONTROLLER_ARRAY[@]}"; do
        if [[ "${RESULTS_TEST1[$i]}" == "FAIL_PERMISSION" ]] || [[ "${RESULTS_TEST2[$i]}" == "FAIL_PERMISSION" ]]; then
            ((CONTROLLERS_WITH_ISSUES++))
        fi
    done

    echo "Controllers with permission issues: $CONTROLLERS_WITH_ISSUES out of $CONTROLLER_COUNT"
    echo ""
    echo "ACTION REQUIRED:"
    echo "  1. Log into each AppDynamics Controller UI"
    echo "  2. Navigate to: Settings → Administration → API Clients"
    echo "  3. Find the OAuth client and assign 'License Admin' role"
    echo "  4. Save and wait 1-2 minutes for permissions to propagate"
    echo "  5. Re-run this script to verify"
    exit 1
else
    echo -e "${YELLOW}⚠️  MIXED RESULTS${NC}"
    echo ""
    echo "Passed: Usage=$TOTAL_PASS_TEST1/$CONTROLLER_COUNT, Grouped=$TOTAL_PASS_TEST2/$CONTROLLER_COUNT"
    exit 2
fi
