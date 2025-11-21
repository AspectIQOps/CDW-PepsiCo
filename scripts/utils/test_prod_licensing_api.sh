#!/bin/bash
#
# Quick Test - PROD Controller Only
# Tests: pepsi-prod.saas.appdynamics.com
#

set -e

# PROD CREDENTIALS
CONTROLLER="pepsi-prod.saas.appdynamics.com"
ACCOUNT="pepsi-prod"
CLIENT_ID="License Dashboard Client Key"
CLIENT_SECRET="c09ac79f-c41d-4674-922b-23a5c35b89c7"
ACCOUNT_ID=""  # Will auto-discover

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "======================================================================"
echo "  AppDynamics Licensing API v1 - PROD Test"
echo "======================================================================"
echo ""
echo "Controller: $CONTROLLER"
echo "Account: $ACCOUNT"
echo ""

# JSON helper
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

# Step 1: OAuth
echo "======================================================================"
echo "  [Step 1/5] Authenticating with OAuth 2.0"
echo "======================================================================"
echo ""
echo "Endpoint: https://${CONTROLLER}/controller/api/oauth/access_token"
echo "Client: ${CLIENT_ID}@${ACCOUNT}"
echo ""

TOKEN_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  "https://${CONTROLLER}/controller/api/oauth/access_token" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}@${ACCOUNT}" \
  -d "client_secret=${CLIENT_SECRET}")

HTTP_STATUS=$(echo "$TOKEN_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$TOKEN_RESPONSE" | sed '/HTTP_STATUS/d')

echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" != "200" ]; then
    echo -e "${RED}❌ FAILED${NC}"
    echo "Response: $BODY"
    exit 1
fi

ACCESS_TOKEN=$(json_get "$BODY" "access_token")
if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}❌ FAILED - No token in response${NC}"
    exit 1
fi

echo -e "${GREEN}✅ SUCCESS${NC}"
echo "Token: ${ACCESS_TOKEN:0:30}... (truncated)"
echo ""

# Step 2: Discover Account ID
echo "======================================================================"
echo "  [Step 2/5] Auto-Discovering Account ID"
echo "======================================================================"
echo ""
echo "Endpoint: /controller/api/accounts/myaccount"
echo ""

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "https://${CONTROLLER}/controller/api/accounts/myaccount" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ]; then
    ACCOUNT_ID=$(json_get "$BODY" "id")
    echo -e "${GREEN}✅ SUCCESS${NC}"
    echo "Account ID: $ACCOUNT_ID"
    echo ""
else
    echo -e "${RED}❌ FAILED${NC}"
    echo "Cannot proceed without Account ID"
    exit 1
fi

# Step 3: Test Account-Level Usage API
echo "======================================================================"
echo "  [Step 3/5] Testing Account-Level Usage API"
echo "======================================================================"
echo ""

DATE_FROM=$(get_date_7_days_ago)
DATE_TO=$(get_date_now)

echo "Endpoint: /controller/licensing/v1/usage/account/${ACCOUNT_ID}"
echo "Date Range: ${DATE_FROM} to ${DATE_TO}"
echo "Granularity: 1440 minutes (daily)"
echo ""

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "https://${CONTROLLER}/controller/licensing/v1/usage/account/${ACCOUNT_ID}?dateFrom=${DATE_FROM}&dateTo=${DATE_TO}&granularityMinutes=1440" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}✅ PASS - API returned license usage data${NC}"
    TEST1="PASS"

    # Show sample data
    if command -v python3 &> /dev/null; then
        echo ""
        echo "Sample Response (first 20 lines):"
        echo "$BODY" | python3 -m json.tool 2>/dev/null | head -20 || echo "$BODY" | head -20
    fi
    echo ""
elif [ "$HTTP_STATUS" = "403" ]; then
    echo -e "${RED}❌ PERMISSION DENIED${NC}"
    ERROR_MSG=$(json_get "$BODY" "errorMessage")
    echo "Error: $ERROR_MSG"
    echo "Fix: Assign 'License Admin' role to OAuth client"
    TEST1="FAIL_PERMISSION"
    echo ""
else
    echo -e "${RED}❌ FAILED${NC}"
    echo "Response: ${BODY:0:200}"
    TEST1="FAIL_OTHER"
    echo ""
fi

# Step 4: Get Application IDs
echo "======================================================================"
echo "  [Step 4/5] Fetching Application IDs"
echo "======================================================================"
echo ""
echo "Endpoint: /controller/rest/applications"
echo ""

APP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "https://${CONTROLLER}/controller/rest/applications?output=JSON" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}")

HTTP_STATUS=$(echo "$APP_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$APP_RESPONSE" | sed '/HTTP_STATUS/d')

echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ]; then
    if command -v python3 &> /dev/null; then
        APP_COUNT=$(echo "$BODY" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        APP_IDS=$(echo "$BODY" | python3 -c "import sys, json; apps = json.load(sys.stdin); print(','.join([str(app['id']) for app in apps if 'id' in app][:5]))" 2>/dev/null || echo "")
    else
        APP_IDS=$(echo "$BODY" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | head -5 | sed 's/.*:\s*//' | tr '\n' ',' | sed 's/,$//')
        APP_COUNT=$(echo "$BODY" | grep -o '"id"' | wc -l | xargs)
    fi
    echo -e "${GREEN}✅ Found $APP_COUNT applications${NC}"
    echo "Using first 5 IDs for test: $APP_IDS"
    echo ""
else
    echo -e "${RED}❌ FAILED to fetch applications${NC}"
    APP_IDS=""
    echo ""
fi

# Step 5: Test Grouped Usage API
echo "======================================================================"
echo "  [Step 5/5] Testing Grouped Usage by Application API"
echo "======================================================================"
echo ""

if [ -z "$APP_IDS" ]; then
    echo -e "${YELLOW}⚠️  SKIPPED (no application IDs)${NC}"
    TEST2="SKIP"
else
    IFS=',' read -ra ID_ARRAY <<< "$APP_IDS"
    QUERY_STRING=""
    for id in "${ID_ARRAY[@]}"; do
        [ -z "$QUERY_STRING" ] && QUERY_STRING="appId=$id" || QUERY_STRING="${QUERY_STRING}&appId=$id"
    done

    echo "Endpoint: /controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id"
    echo "Testing with ${#ID_ARRAY[@]} application IDs"
    echo ""

    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "https://${CONTROLLER}/controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id?${QUERY_STRING}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json")

    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

    echo "HTTP Status: $HTTP_STATUS"

    if [ "$HTTP_STATUS" = "200" ]; then
        echo -e "${GREEN}✅ PASS - API returned per-application data${NC}"
        TEST2="PASS"

        # Show sample data
        if command -v python3 &> /dev/null; then
            echo ""
            echo "Sample Response (first 20 lines):"
            echo "$BODY" | python3 -m json.tool 2>/dev/null | head -20 || echo "$BODY" | head -20
        fi
        echo ""
    elif [ "$HTTP_STATUS" = "403" ]; then
        echo -e "${RED}❌ PERMISSION DENIED${NC}"
        ERROR_MSG=$(json_get "$BODY" "errorMessage")
        echo "Error: $ERROR_MSG"
        echo "Fix: Assign 'License Admin' role to OAuth client"
        TEST2="FAIL_PERMISSION"
        echo ""
    else
        echo -e "${RED}❌ FAILED${NC}"
        echo "Response: ${BODY:0:200}"
        TEST2="FAIL_OTHER"
        echo ""
    fi
fi

# Final Summary
echo "======================================================================"
echo "  FINAL RESULTS - PROD Controller"
echo "======================================================================"
echo ""
echo "Controller: $CONTROLLER"
echo "Account: $ACCOUNT (ID: $ACCOUNT_ID)"
echo ""

if [[ "$TEST1" == "PASS" ]]; then
    echo -e "Account-Level Usage API: ${GREEN}✅ PASS${NC}"
else
    echo -e "Account-Level Usage API: ${RED}❌ ${TEST1}${NC}"
fi

if [[ "$TEST2" == "PASS" ]]; then
    echo -e "Grouped Usage API:       ${GREEN}✅ PASS${NC}"
elif [[ "$TEST2" == "SKIP" ]]; then
    echo -e "Grouped Usage API:       ${YELLOW}⚠️  SKIPPED${NC}"
else
    echo -e "Grouped Usage API:       ${RED}❌ ${TEST2}${NC}"
fi

echo ""
echo "======================================================================"
echo ""

if [[ "$TEST1" == "PASS" ]] && [[ "$TEST2" == "PASS" ]]; then
    echo -e "${GREEN}🎉 SUCCESS! All tests passed on PROD!${NC}"
    echo ""
    echo "The OAuth client has proper licensing API permissions."
    echo ""
    echo "Next Steps:"
    echo "  1. Client can now apply same permissions to other controllers"
    echo "  2. Re-run full test script to verify all controllers"
    exit 0
else
    echo -e "${RED}❌ TESTS FAILED${NC}"
    echo ""
    if [[ "$TEST1" == "FAIL_PERMISSION" ]] || [[ "$TEST2" == "FAIL_PERMISSION" ]]; then
        echo "Client needs to assign 'License Admin' role to the OAuth client:"
        echo "  1. Log into: https://${CONTROLLER}"
        echo "  2. Go to: Settings → Administration → API Clients"
        echo "  3. Find: ${CLIENT_ID}"
        echo "  4. Assign Role: License Admin"
        echo "  5. Save and wait 1-2 minutes"
        echo "  6. Re-run this script"
    fi
    exit 1
fi