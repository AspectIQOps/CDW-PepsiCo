# AppDynamics Licensing API - Manual Testing Guide

## 🎯 Objective

Test the AppDynamics Licensing API v1 endpoints manually and grant necessary permissions to the OAuth client.

---

## ✅ What We've Confirmed So Far

- ✅ API endpoints exist and respond (not 404)
- ✅ OAuth authentication works (not 401)
- ✅ Account ID is correct (193)
- ❌ OAuth client lacks licensing permissions (403 Forbidden)

---

## 📋 Step-by-Step Testing Process

### **Step 1: Load Credentials from AWS SSM**

```bash
# Navigate to project directory
cd /Users/greg/Documents/Greg\'s/Work/GitHub/CDW-PepsiCo

# Load AppDynamics credentials from SSM
export AWS_REGION="us-east-2"
export APPD_CONTROLLERS=$(aws ssm get-parameter \
    --name "/pepsico/appdynamics/CONTROLLER" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text)

export APPD_ACCOUNTS=$(aws ssm get-parameter \
    --name "/pepsico/appdynamics/ACCOUNT" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text)

export APPD_CLIENT_IDS=$(aws ssm get-parameter \
    --name "/pepsico/appdynamics/CLIENT_ID" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text)

export APPD_CLIENT_SECRETS=$(aws ssm get-parameter \
    --name "/pepsico/appdynamics/CLIENT_SECRET" \
    --with-decryption \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text)

export APPD_ACCOUNT_IDS=$(aws ssm get-parameter \
    --name "/pepsico/appdynamics/ACCOUNT_ID" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text)

# Verify credentials loaded
echo "Controller: $APPD_CONTROLLERS"
echo "Account: $APPD_ACCOUNTS"
echo "Account ID: $APPD_ACCOUNT_IDS"
echo "Client ID: $APPD_CLIENT_IDS"
```

**Expected Output:**
```
Controller: pepsi-test.saas.appdynamics.com, pepsico-nonprod.saas.appdynamics.com, pepsicoeu-test.saas.appdynamics.com
Account: pepsi-test, pepsico-nonprod, pepsicoeu-test
Account ID: 193,259,55
Client ID: <your-client-id>
```

---

### **Step 2: Get OAuth Token**

```bash
# Parse first controller values
CONTROLLER=$(echo $APPD_CONTROLLERS | cut -d',' -f1 | xargs)
ACCOUNT=$(echo $APPD_ACCOUNTS | cut -d',' -f1 | xargs)
CLIENT_ID=$(echo $APPD_CLIENT_IDS | cut -d',' -f1 | xargs)
CLIENT_SECRET=$(echo $APPD_CLIENT_SECRETS | cut -d',' -f1 | xargs)
ACCOUNT_ID=$(echo $APPD_ACCOUNT_IDS | cut -d',' -f1 | xargs)

echo "Testing with:"
echo "  Controller: $CONTROLLER"
echo "  Account: $ACCOUNT"
echo "  Account ID: $ACCOUNT_ID"

# Get OAuth token
TOKEN_RESPONSE=$(curl -s -X POST \
  "https://${CONTROLLER}/controller/api/oauth/access_token" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}@${ACCOUNT}" \
  -d "client_secret=${CLIENT_SECRET}")

# Extract access token
ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))")

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Failed to get OAuth token"
    echo "Response: $TOKEN_RESPONSE"
else
    echo "✅ OAuth token obtained successfully"
    echo "Token (first 50 chars): ${ACCESS_TOKEN:0:50}..."
fi
```

**Expected Output:**
```
Testing with:
  Controller: pepsi-test.saas.appdynamics.com
  Account: pepsi-test
  Account ID: 193
✅ OAuth token obtained successfully
Token (first 50 chars): eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI...
```

---

### **Step 3: Test Account-Level Usage API**

```bash
# Calculate date range (last 7 days)
DATE_FROM=$(date -u -v-7d +"%Y-%m-%dT%H:%M:%SZ")
DATE_TO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Testing: /controller/licensing/v1/usage/account/${ACCOUNT_ID}"
echo "Date range: $DATE_FROM to $DATE_TO"

# Make API call
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "https://${CONTROLLER}/controller/licensing/v1/usage/account/${ACCOUNT_ID}?dateFrom=${DATE_FROM}&dateTo=${DATE_TO}&granularityMinutes=1440" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

# Extract status code and body
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo ""
echo "HTTP Status: $HTTP_STATUS"
echo "Response:"
echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
```

**Current Output (Permission Denied):**
```
HTTP Status: 403
Response:
{
    "errorMessage": "User does not have permission to READ entity LICENSE_USAGE for account 193"
}
```

**Expected Output (After Permissions Granted):**
```
HTTP Status: 200
Response:
{
    "accountId": 193,
    "packages": [
        {
            "name": "APM_PRO",
            "unitUsages": [
                {
                    "usageType": "JAVA_AGENT",
                    "granularityInMinutes": 1440,
                    "data": [...]
                }
            ]
        }
    ]
}
```

---

### **Step 4: Get Application IDs**

```bash
echo "Fetching application list from controller..."

APP_RESPONSE=$(curl -s \
  "https://${CONTROLLER}/controller/rest/applications?output=JSON" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}")

# Extract first 5 app IDs
APP_IDS=$(echo "$APP_RESPONSE" | python3 -c "
import sys, json
apps = json.load(sys.stdin)
ids = [str(app['id']) for app in apps if 'id' in app][:5]
print(','.join(ids))
")

echo "Found applications, using first 5 IDs: $APP_IDS"
```

**Expected Output:**
```
Found applications, using first 5 IDs: 2260713,3531313,35810,2260686,1176025
```

---

### **Step 5: Test Grouped Usage by Application API**

```bash
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

echo "Testing: /controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id"
echo "Query: $QUERY_STRING"

# Make API call
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "https://${CONTROLLER}/controller/licensing/v1/account/${ACCOUNT_ID}/grouped-usage/application/by-id?${QUERY_STRING}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

# Extract status code and body
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo ""
echo "HTTP Status: $HTTP_STATUS"
echo "Response:"
echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
```

**Current Output (Permission Denied):**
```
HTTP Status: 403
Response:
{
    "errorMessage": "User does not have permission to READ entity ACCOUNT_LICENSE for account 193"
}
```

**Expected Output (After Permissions Granted):**
```
HTTP Status: 200
Response:
[
    {
        "applicationId": 2260713,
        "applicationName": "My Application",
        "vCPUTotal": 24,
        "hosts": [...],
        "agents": [...]
    },
    ...
]
```

---

### **Step 6: Run Automated Test Script**

Alternatively, use the automated test script we created:

```bash
# Run the test script with SSM credentials
./scripts/utils/test_license_api_with_ssm.sh
```

---

## 🔑 Granting Licensing API Permissions

### **Option A: Via AppDynamics UI (Recommended)**

1. **Log into AppDynamics Controller:**
   ```
   https://pepsi-test.saas.appdynamics.com/controller
   ```

2. **Navigate to API Clients:**
   - Click **Settings** (gear icon, top right)
   - Select **Administration**
   - Click **API Clients**

3. **Find Your OAuth Client:**
   - Look for the client with ID matching your `APPD_CLIENT_IDS`
   - Click on the client to edit

4. **Assign Licensing Permissions:**

   **Method 1: Assign Pre-Built Role**
   - Under "Roles", add:
     - **License Admin** (recommended), OR
     - **Account Owner** (full access)

   **Method 2: Create Custom Role**
   - Click "Create Custom Role"
   - Name: "Licensing API Reader"
   - Grant permissions:
     - ✅ **READ LICENSE_USAGE**
     - ✅ **READ ACCOUNT_LICENSE**
   - Assign this role to your OAuth client

5. **Save Changes**

6. **Re-test** (wait 1-2 minutes for permissions to propagate):
   ```bash
   ./scripts/utils/test_license_api_with_ssm.sh
   ```

---

### **Option B: Via AppDynamics Support Request**

If you don't have admin access to AppDynamics:

**Subject:** Request Licensing API Permissions for OAuth Client

**Body:**
```
Hello AppDynamics Support,

We need to enable Licensing API access for our OAuth client to support
automated license reporting and cost analytics.

Controller: pepsi-test.saas.appdynamics.com
Account: pepsi-test
Account ID: 193
OAuth Client ID: <paste your APPD_CLIENT_IDS value>

Required Permissions:
- READ LICENSE_USAGE (for /controller/licensing/v1/usage/account endpoint)
- READ ACCOUNT_LICENSE (for /controller/licensing/v1/grouped-usage endpoints)

Alternatively, please assign the "License Admin" role to this OAuth client.

Use Case: Automated ETL pipeline for license usage analytics and chargeback reporting.

Thank you!
```

---

### **Option C: Via AppDynamics REST API** (Advanced)

If you have an account with admin permissions, you can grant permissions via API:

```bash
# This requires a user with admin permissions (not the OAuth client we're trying to fix)
# Replace with admin username and password

ADMIN_USER="admin_username@pepsi-test"
ADMIN_PASS="admin_password"

# Get list of roles
curl -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "https://${CONTROLLER}/controller/api/rbac/v1/roles" \
  | python3 -m json.tool

# Find the "License Admin" role ID, then assign it to your client
# (exact API endpoint depends on AppDynamics version)
```

---

## 🧪 Verification Checklist

After permissions are granted, verify both endpoints work:

```bash
# Re-run the automated test
./scripts/utils/test_license_api_with_ssm.sh
```

**Expected Test Results:**
```
======================================================================
TEST SUMMARY
======================================================================
Test 1 - Account-Level Usage API: ✅ PASSED
Test 2 - Grouped Usage API:       ✅ PASSED

✅ Licensing API v1 is accessible!
   Next step: Implement grouped-usage API for per-application data
```

---

## 🚀 Next Steps After Permissions Granted

Once both tests pass:

1. **Re-run ETL Pipeline** to verify end-to-end integration
2. **Implement Grouped Usage API** for per-application license breakdown
3. **Validate Data** in PostgreSQL database
4. **Update Dashboards** to display real license usage

---

## 📞 Troubleshooting

### Problem: "OAuth token not obtained"
**Solution:** Check `APPD_CLIENT_IDS` and `APPD_CLIENT_SECRETS` in SSM

### Problem: Still getting 403 after granting permissions
**Solution:**
- Wait 2-5 minutes for permission propagation
- Clear OAuth token cache by getting a new token
- Verify role was saved in AppDynamics UI

### Problem: 404 Not Found
**Solution:**
- Verify controller URL is correct
- Check AppDynamics version supports Licensing API v1
- Contact AppDynamics support to confirm API availability

### Problem: Different error message
**Solution:**
- Copy the full error response
- Search AppDynamics documentation
- Contact AppDynamics support

---

## 📚 Related Documentation

- [AppDynamics License API Research](APPDYNAMICS_LICENSE_API_RESEARCH.md)
- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [Account ID Discovery Guide](../scripts/utils/README_ACCOUNT_ID_DISCOVERY.md)

---

**Created:** 2025-11-20
**Last Updated:** 2025-11-20
**Status:** Waiting for licensing permissions to be granted
