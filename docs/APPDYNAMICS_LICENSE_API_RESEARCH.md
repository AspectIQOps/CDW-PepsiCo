# AppDynamics License API - Comprehensive Research

## Executive Summary

The AppDynamics Licensing API **DOES EXIST** and provides multiple endpoints for retrieving license usage data. However, the endpoint we tried (`/controller/licensing/usage/account/{accountId}`) appears to be **missing the `/v1/` version prefix**.

---

## 🎯 Recommended API Endpoints

### 1. **Time-Series Usage Data (What We Need)**

**Endpoint:**
```
GET /controller/licensing/v1/usage/account/{accountId}
```

**Parameters:**
- `dateFrom` - ISO 8601 date-time string (e.g., "2024-01-01T00:00:00Z")
- `dateTo` - ISO 8601 date-time string
- `granularityMinutes` - Integer (e.g., 60 for hourly, 1440 for daily)
- `includeEntityTypes` - Boolean (optional)
- `includeConsumptionBased` - Boolean (optional)

**Example:**
```bash
curl --user <user>@<account>:<password> -X GET \
  "https://pepsi-test.saas.appdynamics.com/controller/licensing/v1/usage/account/193?\
dateFrom=2024-01-01T00:00:00Z&\
dateTo=2024-12-31T23:59:59Z&\
granularityMinutes=1440"
```

**Response Structure:**
```json
{
  "accountId": 193,
  "licenseRule": {
    "id": "string",
    "name": "string",
    "licenseKey": "string"
  },
  "packages": [
    {
      "name": "APM_PRO",
      "unitUsages": [
        {
          "usageType": "JAVA_AGENT",
          "granularityInMinutes": 1440,
          "data": [
            {
              "timestamp": "2024-01-01T00:00:00Z",
              "provisioned": {
                "min": 100,
                "max": 150,
                "avg": 125,
                "count": 24
              },
              "used": {
                "min": 80,
                "max": 145,
                "avg": 112,
                "count": 24
              }
            }
          ]
        }
      ]
    }
  ]
}
```

---

### 2. **Grouped Usage by Application (Alternative)**

**Endpoint:**
```
GET /controller/licensing/v1/account/{accountId}/grouped-usage/application/by-id
```

**Parameters:**
- `appId` - Array of application IDs
- `includeAgents` - Boolean (optional)

**Example:**
```bash
curl --user <user>@<account>:<password> -X GET \
  "https://pepsi-test.saas.appdynamics.com/controller/licensing/v1/account/193/grouped-usage/application/by-id?appId=123&appId=456"
```

**Response:**
- vCPU totals per application
- Application details (ID, name)
- Nodes, containers, agents
- Host breakdown

---

### 3. **Grouped Usage by Application Name**

**Endpoint:**
```
GET /controller/licensing/v1/account/{accountId}/grouped-usage/application/by-name
```

**Parameters:**
- `appName` - URL-encoded array of application names
- `includeAgents` - Boolean (optional)

**Example:**
```bash
curl --user <user>@<account>:<password> -X GET \
  "https://pepsi-test.saas.appdynamics.com/controller/licensing/v1/account/193/grouped-usage/application/by-name?appName=MyApp"
```

---

### 4. **EUM-Specific License API (Browser/Mobile/Synthetic)**

**Endpoint:**
```
GET /v2/account/<EUM_Account_Name>/license
```

**Base URL for SaaS:**
```
https://api.eum-appdynamics.com/v2/account/{EUM_ACCOUNTNAME}/license
```

**Authentication:**
- Different from controller APIs
- Uses EUM account name and license key

**Query Parameters:**
```
?timeRange=last_1_hour.BEFORE_NOW.-1.-1.60
?timeRange=Custom_Time_Range.BETWEEN_TIMES.[START_EPOCH].[END_EPOCH].120
```

**Response Fields:**
- `webAllocatedPageViews` / `webConsumedPageViews`
- `allocatedMobileAgents` / `consumedMobileAgents`
- `allocatedSyntheticTime` / `consumedSyntheticTime`

---

## 🔍 Key Findings

### Why Our Original Endpoint Failed

**We tried:**
```
/controller/licensing/usage/account/193
```

**Should be:**
```
/controller/licensing/v1/usage/account/193
```

**Missing:** The `/v1/` version prefix!

---

## 📝 Authentication Methods

### 1. **OAuth 2.0 (What We're Using)**
```python
headers = {
    'Authorization': f'Bearer {access_token}',
    'Content-Type': 'application/json'
}
```

### 2. **Basic Auth (Alternative)**
```bash
--user <username>@<accountName>:<password>
```

**Note:** OAuth is preferred for production use.

---

## 🎪 API Browser / Swagger UI

**Access the interactive API documentation:**
```
https://pepsi-test.saas.appdynamics.com/api-docs/index.html
```

This provides:
- Full API reference
- Try-it-now functionality
- Request/response examples
- Parameter documentation

---

## 🚦 Next Steps

### Step 1: Update ETL Script
Change the endpoint from:
```python
f"licensing/usage/account/{account_id}"
```

To:
```python
f"licensing/v1/usage/account/{account_id}"
```

### Step 2: Add Required Parameters
```python
params = {
    'dateFrom': '2024-01-01T00:00:00Z',
    'dateTo': '2024-12-31T23:59:59Z',
    'granularityMinutes': 1440  # Daily aggregation
}
```

### Step 3: Test the Fixed Endpoint
Run the ETL again to verify the corrected endpoint works.

### Step 4: Alternative - Use Grouped Usage API
If time-series API still fails, try the grouped-usage endpoint which provides current snapshot data.

---

## 📚 Official Documentation Links

1. **License API Reference:**
   - https://docs.appdynamics.com/appd/onprem/24.x/25.2/en/extend-appdynamics/splunk-appdynamics-apis/license-api

2. **Swagger/API Browser:**
   - https://{controller}/api-docs/index.html

3. **Community Knowledge Base:**
   - How to check license usage: https://community.appdynamics.com/t5/Knowledge-Base/How-do-I-check-my-license-usage-at-the-account-level/ta-p/34492
   - License usage by application: https://community.appdynamics.com/t5/Knowledge-Base/How-do-I-find-license-usage-by-applications-for-each-Controller/ta-p/24128

---

## ⚠️ Important Notes

### Licensing Model Differences

**Infrastructure-Based Licensing (IBL):**
- Uses vCPU counts
- Grouped-usage API works well

**Agent-Based Licensing (ABL):**
- Limited API support
- May require workarounds using node/agent availability metrics

### SaaS vs On-Premise

- **SaaS:** Endpoints confirmed to work with OAuth 2.0
- **On-Premise:** May have different base URLs

### Permissions Required

- **View license info:** `account_owner` or `administration` role
- **Modern interface:** `Company Admin` or `License Admin` role

---

## 🧪 Testing Recommendations

1. **Test with Swagger UI first** - Use the built-in API browser to verify endpoints work
2. **Start with small date range** - Test with 1 day before querying 12 months
3. **Check granularity** - Higher granularity (e.g., 60 min) = more data points = larger response
4. **Verify response format** - Ensure the response structure matches our data model

---

## 💡 Alternative Data Sources

If APIs continue to fail:

1. **UI Export** - Check if license usage can be exported as CSV from the Controller UI
2. **Analytics Search** - Use AppDynamics Analytics to query license metrics
3. **Custom Dashboard API** - Export data from existing license dashboards
4. **Support Request** - Contact AppDynamics support to enable API access

---

**Created:** 2025-11-20
**Status:** Ready for Implementation
**Priority:** HIGH - Core requirement for cost analytics
