#!/bin/bash
#
# Standalone AppDynamics Licensing API v1 Test Script
# Works on Linux, macOS, Windows (Git Bash/WSL)
# No AWS dependencies - credentials entered interactively
#
# Usage:
#   bash test_all_controllers_standalone.sh
#
# Windows users: Run in Git Bash or WSL
#

set -e

# Colors (work on Linux, macOS, Git Bash)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear

echo ""
echo "======================================================================"
echo "  AppDynamics Licensing API v1 - Standalone Test"
echo "  Cross-Platform (Linux/macOS/Windows Git Bash/WSL)"
echo "======================================================================"
echo ""
echo "This script will test the AppDynamics Licensing API v1 endpoints"
echo "for all configured controllers."
echo ""
echo "You will be prompted to enter your credentials."
echo ""
echo -e "${YELLOW}Press ENTER to continue or Ctrl+C to exit...${NC}"
read -r

# ======================================================================
# Prompt for Credentials
# ======================================================================

echo ""
echo "======================================================================"
echo "  Enter AppDynamics Credentials"
echo "======================================================================"
echo ""
echo "Enter comma-separated values for multiple controllers."
echo "Example: controller1.com,controller2.com,controller3.com"
echo ""

# Controllers
echo -e "${CYAN}Enter Controller URLs (comma-separated):${NC}"
echo "Example: pepsi-test.saas.appdynamics.com,pepsico-nonprod.saas.appdynamics.com"
read -r APPD_CONTROLLERS

if [ -z "$APPD_CONTROLLERS" ]; then
    echo -e "${RED}❌ Error: Controllers required${NC}"
    exit 1
fi

# Accounts
echo ""
echo -e "${CYAN}Enter Account Names (comma-separated, same order as controllers):${NC}"
echo "Example: pepsi-test,pepsico-nonprod"
read -r APPD_ACCOUNTS

if [ -z "$APPD_ACCOUNTS" ]; then
    echo -e "${RED}❌ Error: Accounts required${NC}"
    exit 1
fi

# Account IDs
echo ""
echo -e "${CYAN}Enter Account IDs (comma-separated, same order as controllers):${NC}"
echo "Example: 193,259"
read -r APPD_ACCOUNT_IDS

if [ -z "$APPD_ACCOUNT_IDS" ]; then
    echo -e "${RED}❌ Error: Account IDs required${NC}"
    exit 1
fi

# Client IDs
echo ""
echo -e "${CYAN}Enter OAuth Client IDs (comma-separated, same order as controllers):${NC}"
read -r APPD_CLIENT_IDS

if [ -z "$APPD_CLIENT_IDS" ]; then
    echo -e "${RED}❌ Error: Client IDs required${NC}"
    exit 1
fi

# Client Secrets
echo ""
echo -e "${CYAN}Enter OAuth Client Secrets (comma-separated, same order as controllers):${NC}"
echo -e "${YELLOW}(Input will be hidden)${NC}"
read -rs APPD_CLIENT_SECRETS

if [ -z "$APPD_CLIENT_SECRETS" ]; then
    echo -e "${RED}❌ Error: Client Secrets required${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Credentials entered${NC}"

# ======================================================================
# Parse and Validate
# ======================================================================

echo ""
echo "======================================================================"
echo "  Validating Configuration"
echo "======================================================================"
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
ACCOUNT_COUNT=${#ACCOUNT_ARRAY[@]}
CLIENT_ID_COUNT=${#CLIENT_ID_ARRAY[@]}
CLIENT_SECRET_COUNT=${#CLIENT_SECRET_ARRAY[@]}
ACCOUNT_ID_COUNT=${#ACCOUNT_ID_ARRAY[@]}

# Validate counts match
if [ $CONTROLLER_COUNT -ne $ACCOUNT_COUNT ] || \
   [ $CONTROLLER_COUNT -ne $CLIENT_ID_COUNT ] || \
   [ $CONTROLLER_COUNT -ne $CLIENT_SECRET_COUNT ] || \
   [ $CONTROLLER_COUNT -ne $ACCOUNT_ID_COUNT ]; then
    echo -e "${RED}❌ Error: Mismatched credential counts!${NC}"
    echo "  Controllers: $CONTROLLER_COUNT"
    echo "  Accounts: $ACCOUNT_COUNT"
    echo "  Account IDs: $ACCOUNT_ID_COUNT"
    echo "  Client IDs: $CLIENT_ID_COUNT"
    echo "  Client Secrets: $CLIENT_SECRET_COUNT"
    echo ""
    echo "All counts must match. Please re-run the script."
    exit 1
fi

echo -e "${GREEN}✅ Found ${CONTROLLER_COUNT} controllers to test${NC}"
echo ""
for i in "${!CONTROLLER_ARRAY[@]}"; do
    echo "  $((i+1)). ${CONTROLLER_ARRAY[$i]}"
    echo "     Account: ${ACCOUNT_ARRAY[$i]}"
    echo "     Account ID: ${ACCOUNT_ID_ARRAY[$i]}"
    echo "     Client ID: ${CLIENT_ID_ARRAY[$i]:0:20}..."
done
echo ""
echo -e "${YELLOW}Press ENTER to start testing...${NC}"
read -r

# ======================================================================
# Helper Function: JSON Parse (works without jq)
# ======================================================================

json_get() {
    local json="$1"
    local key="$2"

    # Try python3 first (most reliable)
    if command -v python3 &> /dev/null; then
        echo "$json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('$key', ''))" 2>/dev/null || echo ""
    # Try python (Python 2)
    elif command -v python &> /dev/null; then
        echo "$json" | python -c "import sys, json; print json.load(sys.stdin).get('$key', '')" 2>/dev/null || echo ""
    # Fallback to grep/sed (less reliable but works)
    else
        echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"\([^"]*\)".*/\1/' | head -1
    fi
}

json_array_length() {
    local json="$1"

    if command -v python3 &> /dev/null; then
        echo "$json" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0"
    elif command -v python &> /dev/null; then
        echo "$json" | python -c "import sys, json; print len(json.load(sys.stdin))" 2>/dev/null || echo "0"
    else
        # Rough estimate by counting opening braces
        echo "$json" | grep -o '{' | wc -l | xargs
    fi
}

json_pretty() {
    local json="$1"

    if command -v python3 &> /dev/null; then
        echo "$json" | python3 -m json.tool 2>/dev/null || echo "$json"
    elif command -v python &> /dev/null; then
        echo "$json" | python -m json.tool 2>/dev/null || echo "$json"
    else
        echo "$json"
    fi
}

# ======================================================================
# Helper Function: Calculate Dates (cross-platform)
# ======================================================================

get_date_7_days_ago() {
    if command -v python3 &> /dev/null; then
        python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow() - timedelta(days=7)).strftime('%Y-%m-%dT%H:%M:%SZ'))"
    elif command -v python &> /dev/null; then
        python -c "from datetime import datetime, timedelta; print (datetime.utcnow() - timedelta(days=7)).strftime('%Y-%m-%dT%H:%M:%SZ')"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        date -u -v-7d +"%Y-%m-%dT%H:%M:%SZ"
    else
        date -u -d '7 days ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT00:00:00Z"
    fi
}

get_date_now() {
    if command -v python3 &> /dev/null; then
        python3 -c "from datetime import datetime; print(datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'))"
    elif command -v python &> /dev/null; then
        python -c "from datetime import datetime; print datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')"
    else
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# ======================================================================
# Function: Test Single Controller
# ======================================================================

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

    ACCESS_TOKEN=$(json_get "$BODY" "access_token")

    if [ -z "$ACCESS_TOKEN" ]; then
        echo -e "${RED}❌ Failed to parse access token${NC}"
        echo "Response: $BODY"
        return 1
    fi

    echo -e "${GREEN}✅ OAuth token obtained${NC}"

    # Calculate date range
    DATE_FROM=$(get_date_7_days_ago)
    DATE_TO=$(get_date_now)

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
            echo "  Response preview:"
            json_pretty "$BODY" | head -20
            TEST1_RESULT="PASS"
            ;;
        403)
            echo -e "  Result: ${RED}❌ PERMISSION DENIED${NC}"
            ERROR_MSG=$(json_get "$BODY" "errorMessage")
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
        APP_COUNT=$(json_array_length "$BODY")
        echo -e "  Result: ${GREEN}✅ Found $APP_COUNT applications${NC}"

        # Extract first 5 app IDs
        if command -v python3 &> /dev/null; then
            APP_IDS=$(echo "$BODY" | python3 -c "
import sys, json
apps = json.load(sys.stdin)
ids = [str(app['id']) for app in apps if 'id' in app][:5]
print(','.join(ids))
" 2>/dev/null || echo "")
        elif command -v python &> /dev/null; then
            APP_IDS=$(echo "$BODY" | python -c "
import sys, json
apps = json.load(sys.stdin)
ids = [str(app['id']) for app in apps if 'id' in app][:5]
print ','.join(ids)
" 2>/dev/null || echo "")
        else
            # Fallback: extract first app ID using grep
            APP_IDS=$(echo "$BODY" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | head -5 | sed 's/.*:\s*//' | tr '\n' ',' | sed 's/,$//')
        fi
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
                echo "  Response preview:"
                json_pretty "$BODY" | head -20
                TEST2_RESULT="PASS"
                ;;
            403)
                echo -e "  Result: ${RED}❌ PERMISSION DENIED${NC}"
                ERROR_MSG=$(json_get "$BODY" "errorMessage")
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

    # Summary
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
    echo "The AppDynamics Licensing API v1 is fully accessible."
    echo ""
    echo "Next Steps:"
    echo "  1. Implement ETL integration for per-application license data"
    echo "  2. Run the full ETL pipeline"
    echo "  3. Validate data in database"
    exit 0
elif [ $TOTAL_FAIL_PERMISSION_TEST1 -gt 0 ] || [ $TOTAL_FAIL_PERMISSION_TEST2 -gt 0 ]; then
    echo -e "${RED}❌ PERMISSION ISSUES DETECTED${NC}"
    echo ""
    echo "Controllers with permission issues:"
    echo "  Account-Level API: $TOTAL_FAIL_PERMISSION_TEST1 / $CONTROLLER_COUNT"
    echo "  Grouped Usage API: $TOTAL_FAIL_PERMISSION_TEST2 / $CONTROLLER_COUNT"
    echo ""
    echo "Required Permissions:"
    echo "  - READ LICENSE_USAGE"
    echo "  - READ ACCOUNT_LICENSE"
    echo ""
    echo "How to Fix:"
    echo "  1. Log into each AppDynamics Controller UI"
    echo "  2. Navigate to: Settings → Administration → API Clients"
    echo "  3. For each OAuth client, assign 'License Admin' role"
    echo "  4. Save and wait 1-2 minutes for permissions to propagate"
    echo "  5. Re-run this test script"
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
