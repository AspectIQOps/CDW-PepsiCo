#!/bin/bash
#
# Test ALL PROD Controllers - Quick Assessment for Demo
# Tests all 3 production environments
#

set -e

# PROD CREDENTIALS
CONTROLLERS="pepsi-prod.saas.appdynamics.com,pepsico-prod.saas.appdynamics.com,pepsicoeu-prod.saas.appdynamics.com"
ACCOUNTS="pepsi-prod,pepsico-prod,pepsicoeu-prod"
CLIENT_IDS="License Dashboard Client Key,License Dashboard Client Key,License Dashboard Client Key"
CLIENT_SECRETS="c09ac79f-c41d-4674-922b-23a5c35b89c7,8ca9e002-fb1a-490b-a314-c8e8c956984e,9ddf4c7d-4552-446a-a484-ce1eb1bfcf24"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "======================================================================"
echo "  PROD Controllers - License API Assessment"
echo "  For Demo Readiness Evaluation"
echo "======================================================================"
echo ""

# Parse arrays
IFS=',' read -ra CONTROLLER_ARRAY <<< "$CONTROLLERS"
IFS=',' read -ra ACCOUNT_ARRAY <<< "$ACCOUNTS"
IFS=',' read -ra CLIENT_ID_ARRAY <<< "$CLIENT_IDS"
IFS=',' read -ra CLIENT_SECRET_ARRAY <<< "$CLIENT_SECRETS"

# Trim whitespace
for i in "${!CONTROLLER_ARRAY[@]}"; do
    CONTROLLER_ARRAY[$i]=$(echo "${CONTROLLER_ARRAY[$i]}" | xargs)
    ACCOUNT_ARRAY[$i]=$(echo "${ACCOUNT_ARRAY[$i]}" | xargs)
    CLIENT_ID_ARRAY[$i]=$(echo "${CLIENT_ID_ARRAY[$i]}" | xargs)
    CLIENT_SECRET_ARRAY[$i]=$(echo "${CLIENT_SECRET_ARRAY[$i]}" | xargs)
done

CONTROLLER_COUNT=${#CONTROLLER_ARRAY[@]}

# JSON helper
json_get() {
    if command -v python3 &> /dev/null; then
        echo "$1" | python3 -c "import sys, json; print(json.load(sys.stdin).get('$2', ''))" 2>/dev/null || echo ""
    else
        echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"\([^"]*\)".*/\1/' | head -1
    fi
}

# Results arrays
RESULTS_OAUTH=()
RESULTS_ACCOUNT_ID=()
RESULTS_APPS=()
RESULTS_LICENSE_API=()
RESULTS_GROUPED_API=()

# Test each controller
for i in "${!CONTROLLER_ARRAY[@]}"; do
    CONTROLLER="${CONTROLLER_ARRAY[$i]}"
    ACCOUNT="${ACCOUNT_ARRAY[$i]}"
    CLIENT_ID="${CLIENT_ID_ARRAY[$i]}"
    CLIENT_SECRET="${CLIENT_SECRET_ARRAY[$i]}"

    echo ""
    echo -e "${CYAN}======================================================================"
    echo -e "  Controller $((i+1))/$CONTROLLER_COUNT: $CONTROLLER"
    echo -e "======================================================================${NC}"
    echo ""

    # OAuth
    echo "Testing OAuth authentication..."
    TOKEN_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
      "https://${CONTROLLER}/controller/api/oauth/access_token" \
      -d "grant_type=client_credentials" \
      -d "client_id=${CLIENT_ID}@${ACCOUNT}" \
      -d "client_secret=${CLIENT_SECRET}")

    HTTP_STATUS=$(echo "$TOKEN_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$TOKEN_RESPONSE" | sed '/HTTP_STATUS/d')

    if [ "$HTTP_STATUS" = "200" ]; then
        ACCESS_TOKEN=$(json_get "$BODY" "access_token")
        if [ -n "$ACCESS_TOKEN" ]; then
            echo -e "  OAuth: ${GREEN}✅ SUCCESS${NC}"
            RESULTS_OAUTH+=("PASS")
        else
            echo -e "  OAuth: ${RED}❌ FAILED (no token)${NC}"
            RESULTS_OAUTH+=("FAIL")
            continue
        fi
    else
        echo -e "  OAuth: ${RED}❌ FAILED (HTTP $HTTP_STATUS)${NC}"
        RESULTS_OAUTH+=("FAIL")
        continue
    fi

    # Account ID Discovery
    echo "Discovering Account ID..."
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "https://${CONTROLLER}/controller/api/accounts/myaccount" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")

    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

    if [ "$HTTP_STATUS" = "200" ]; then
        ACCOUNT_ID=$(json_get "$BODY" "id")
        echo -e "  Account ID: ${GREEN}✅ $ACCOUNT_ID${NC}"
        RESULTS_ACCOUNT_ID+=("$ACCOUNT_ID")
    else
        echo -e "  Account ID: ${RED}❌ FAILED${NC}"
        RESULTS_ACCOUNT_ID+=("N/A")
        continue
    fi

    # Applications
    echo "Fetching applications..."
    APP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "https://${CONTROLLER}/controller/rest/applications?output=JSON" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")

    HTTP_STATUS=$(echo "$APP_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
    BODY=$(echo "$APP_RESPONSE" | sed '/HTTP_STATUS/d')

    if [ "$HTTP_STATUS" = "200" ]; then
        if command -v python3 &> /dev/null; then
            APP_COUNT=$(echo "$BODY" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
            APP_IDS=$(echo "$BODY" | python3 -c "import sys, json; apps = json.load(sys.stdin); print(','.join([str(app['id']) for app in apps if 'id' in app][:3]))" 2>/dev/null || echo "")
        else
            APP_IDS=$(echo "$BODY" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | head -3 | sed 's/.*:\s*//' | tr '\n' ',' | sed 's/,$//')
            APP_COUNT=$(echo "$BODY" | grep -o '"id"' | wc -l | xargs)
        fi
        echo -e "  Applications: ${GREEN}✅ $APP_COUNT found${NC}"
        RESULTS_APPS+=("$APP_COUNT")
    else
        echo -e "  Applications: ${RED}❌ FAILED${NC}"
        RESULTS_APPS+=("0")
        APP_IDS=""
    fi

    # License API
    echo "Testing License Usage API..."
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      "https://${CONTROLLER}/controller/licensing/v1/usage/account/${ACCOUNT_ID}?granularityMinutes=1440" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")

    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)

    if [ "$HTTP_STATUS" = "200" ]; then
        echo -e "  License API: ${GREEN}✅ ACCESSIBLE${NC}"
        RESULTS_LICENSE_API+=("PASS")
    elif [ "$HTTP_STATUS" = "403" ]; then
        echo -e "  License API: ${RED}❌ PERMISSION DENIED${NC}"
        RESULTS_LICENSE_API+=("NO_PERMISSION")
    else
        echo -e "  License API: ${RED}❌ FAILED (HTTP $HTTP_STATUS)${NC}"
        RESULTS_LICENSE_API+=("FAIL")
    fi

    # Grouped Usage API
    if [ -n "$APP_IDS" ]; then
        echo "Testing Grouped Usage API..."
        IFS=',' read -ra ID_ARRAY <<< "$APP_IDS"
        QUERY_STRING=""
        for id in "${ID_ARRAY[@]}"; do
            [ -z "$QUERY_STRING" ] && QUERY_STRING="appId=$id" || QUERY_STRING="${QUERY_STRING}&appId=$id"
        done

        RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
          "https://${CONTROLLER}/controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id?${QUERY_STRING}" \
          -H "Authorization: Bearer ${ACCESS_TOKEN}")

        HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)

        if [ "$HTTP_STATUS" = "200" ]; then
            echo -e "  Grouped API: ${GREEN}✅ ACCESSIBLE${NC}"
            RESULTS_GROUPED_API+=("PASS")
        elif [ "$HTTP_STATUS" = "403" ]; then
            echo -e "  Grouped API: ${RED}❌ PERMISSION DENIED${NC}"
            RESULTS_GROUPED_API+=("NO_PERMISSION")
        elif [ "$HTTP_STATUS" = "500" ]; then
            echo -e "  Grouped API: ${YELLOW}⚠️  NOT SUPPORTED (500 Error)${NC}"
            RESULTS_GROUPED_API+=("NOT_SUPPORTED")
        else
            echo -e "  Grouped API: ${RED}❌ FAILED (HTTP $HTTP_STATUS)${NC}"
            RESULTS_GROUPED_API+=("FAIL")
        fi
    else
        RESULTS_GROUPED_API+=("SKIP")
    fi
done

# Summary
echo ""
echo ""
echo "======================================================================"
echo "  DEMO READINESS ASSESSMENT - SUMMARY"
echo "======================================================================"
echo ""

for i in "${!CONTROLLER_ARRAY[@]}"; do
    echo -e "${CYAN}Controller $((i+1)): ${CONTROLLER_ARRAY[$i]}${NC}"
    echo "  Account: ${ACCOUNT_ARRAY[$i]} (ID: ${RESULTS_ACCOUNT_ID[$i]})"
    echo "  OAuth: ${RESULTS_OAUTH[$i]}"
    echo "  Applications: ${RESULTS_APPS[$i]}"
    echo "  License API: ${RESULTS_LICENSE_API[$i]}"
    echo "  Grouped API: ${RESULTS_GROUPED_API[$i]}"
    echo ""
done

echo "======================================================================"
echo "  WHAT CAN BE DEMOED TODAY?"
echo "======================================================================"
echo ""

# Count successes
LICENSE_API_SUCCESS=0
GROUPED_API_SUCCESS=0
TOTAL_APPS=0

for i in "${!CONTROLLER_ARRAY[@]}"; do
    [[ "${RESULTS_LICENSE_API[$i]}" == "PASS" ]] && ((LICENSE_API_SUCCESS++)) || true
    [[ "${RESULTS_GROUPED_API[$i]}" == "PASS" ]] && ((GROUPED_API_SUCCESS++)) || true
    TOTAL_APPS=$((TOTAL_APPS + ${RESULTS_APPS[$i]}))
done

if [ $LICENSE_API_SUCCESS -gt 0 ] && [ $GROUPED_API_SUCCESS -gt 0 ]; then
    echo -e "${GREEN}🎉 FULL SOW COMPLIANCE POSSIBLE!${NC}"
    echo ""
    echo "✅ $LICENSE_API_SUCCESS/$CONTROLLER_COUNT controllers have License API access"
    echo "✅ $GROUPED_API_SUCCESS/$CONTROLLER_COUNT controllers have Grouped API access"
    echo "✅ Total applications available: $TOTAL_APPS"
    echo ""
    echo "Demo-Ready Features:"
    echo "  ✅ Real license usage data (account-level)"
    echo "  ✅ Per-application license breakdown"
    echo "  ✅ All 8 SOW dashboards"
    echo "  ✅ Cost allocation by department/H-code"
    echo "  ✅ Chargeback reports"
    echo ""
    echo "Recommendation: Run full ETL pipeline and demo complete solution"

elif [ $LICENSE_API_SUCCESS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  PARTIAL ACCESS - ACCOUNT-LEVEL DATA ONLY${NC}"
    echo ""
    echo "✅ $LICENSE_API_SUCCESS/$CONTROLLER_COUNT controllers have License API access"
    echo "❌ $GROUPED_API_SUCCESS/$CONTROLLER_COUNT controllers have Grouped API access"
    echo "✅ Total applications available: $TOTAL_APPS"
    echo ""
    echo "Demo-Ready Features:"
    echo "  ✅ Real account-level license usage"
    echo "  ✅ Usage trends over time"
    echo "  ⚠️  Per-application breakdown (using node-based distribution)"
    echo "  ⚠️  Dashboards functional but using estimated per-app data"
    echo ""
    echo "Recommendation: Demo with node-based allocation as interim solution"
    echo "               Account-level API validates totals are correct"

else
    echo -e "${RED}❌ NO LICENSE API ACCESS${NC}"
    echo ""
    echo "❌ $LICENSE_API_SUCCESS/$CONTROLLER_COUNT controllers have License API access"
    echo "✅ Total applications available: $TOTAL_APPS"
    echo ""
    echo "Demo Options:"
    echo "  1. Use existing demo/test environment data"
    echo "  2. Demo architecture and design only"
    echo "  3. Request client grant permissions before demo"
    echo ""
    echo "Cannot demo with real PROD data today"
fi

echo ""
echo "======================================================================"
exit 0