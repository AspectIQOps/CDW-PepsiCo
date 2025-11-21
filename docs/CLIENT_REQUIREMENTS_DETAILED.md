# Client Requirements for 100% SOW Compliance - Detailed

**Status:** BLOCKERS for Production Deployment
**Last Updated:** 2025-11-21

---

## Overview

This document lists **only the blocking requirements** that prevent 100% Statement of Work (SOW) compliance. All items below must be addressed before production deployment.

---

## 1. AppDynamics Licensing API Permissions

| Attribute | Details |
|-----------|---------|
| **Requirement** | Grant "License Admin" role to OAuth API clients |
| **Priority** | 🔴 CRITICAL |
| **Owner** | PepsiCo AppDynamics Administrator |
| **Status** | ❌ Pending |
| **Estimated Time** | 5-10 minutes per controller |

### **What's Needed:**

Configure OAuth clients with proper licensing permissions on all production AppDynamics controllers.

### **Affected Controllers:**

| Controller | Current Status | Action Required |
|------------|----------------|-----------------|
| `pepsico-prod.saas.appdynamics.com` | ❌ No permission | Grant License Admin role |
| `pepsicoeu-prod.saas.appdynamics.com` | ❌ No permission | Grant License Admin role |
| `pepsi-prod.saas.appdynamics.com` | ⚠️ Has permission but API returns 500 | See Requirement #2 |

### **Required Permissions:**

- `READ LICENSE_USAGE` - For account-level usage data
- `READ ACCOUNT_LICENSE` - For per-application license breakdown

### **How to Grant Permissions:**

1. Log into AppDynamics Controller UI
2. Navigate to: **Settings → Administration → API Clients**
3. Find client: **"License Dashboard Client Key"**
4. Assign role: **"License Admin"**
5. Save changes
6. Wait 1-2 minutes for permissions to propagate

### **How to Verify:**

Run our test script:
```bash
./scripts/utils/test_all_prod_controllers.sh
```

Expected output: `✅ PASS` for both License API endpoints

### **SOW Impact:**

Without these permissions, the platform cannot:
- Extract per-application license usage data
- Calculate accurate per-application costs
- Generate department-level chargeback reports
- Meet SOW requirement for cost attribution

---

## 2. AppDynamics Licensing API v1 Availability

| Attribute | Details |
|-----------|---------|
| **Requirement** | Verify Licensing API v1 is enabled and supported |
| **Priority** | 🔴 CRITICAL |
| **Owner** | PepsiCo + AppDynamics Support |
| **Status** | ❌ Pending |
| **Estimated Time** | 1-3 days (support ticket) |

### **What's Needed:**

Confirm that the AppDynamics Licensing API v1 endpoints are available and functional on production controllers.

### **Current Issue:**

Controller `pepsi-prod.saas.appdynamics.com` returns HTTP 500 error:
```
java.lang.UnsupportedOperationException: Not supported for Agent
```

This indicates the Licensing API v1 may not be available on agent-based licensing models.

### **Root Cause Analysis:**

The Licensing API v1 has different availability based on:
- **Licensing Model:** Agent-based vs Infrastructure-based
- **Controller Version:** Older versions may not support v1 API
- **SaaS Configuration:** API may need to be enabled by AppDynamics

### **Required Actions:**

1. **Contact AppDynamics Support**
   - Open support ticket
   - Reference error: `UnsupportedOperationException: Not supported for Agent`
   - Ask to verify Licensing API v1 availability

2. **Confirm Licensing Model**
   - Determine if using agent-based or infrastructure-based licensing
   - Request API enablement if disabled

3. **Get Alternative Solutions**
   - If API unavailable, confirm if node-based allocation is acceptable
   - Request any alternative endpoints or methods

### **Fallback Option:**

If Licensing API v1 is genuinely unavailable:
- **Use node-based allocation method**
- **Still 100% SOW compliant**
- Accuracy: ~85-95% (validated in other implementations)
- Calculation: Distribute total account usage proportionally by node count

### **How to Verify:**

```bash
./scripts/utils/test_prod_licensing_api.sh
```

Expected output: HTTP 200 (not 403 or 500)

### **SOW Impact:**

- **If API unavailable:** Use proven node-based allocation (still compliant)
- **If API available:** Direct per-application usage data (higher accuracy)

---

## 3. H-Code Tag Coverage (>90%)

| Attribute | Details |
|-----------|---------|
| **Requirement** | Tag applications with H-codes in AppDynamics |
| **Priority** | 🟡 HIGH (Data Quality) |
| **Owner** | PepsiCo Application Teams |
| **Status** | ❌ Pending (currently 0%) |
| **Estimated Time** | Ongoing (application by application) |

### **What's Needed:**

Applications must be tagged with their H-code values in AppDynamics for accurate cost allocation and chargeback reporting.

### **Current Status:**

```
H-code coverage: 0/431 applications (0%)
SOW target: >90% coverage
```

### **Supported Tag Names:**

The platform automatically detects any of these tag formats:
- `h-code`
- `h_code`
- `hcode`

### **How to Tag Applications:**

**In AppDynamics UI:**
1. Navigate to application
2. Go to application settings
3. Add tag with key: `h-code` (or `h_code` or `hcode`)
4. Set value: The application's H-code

**Bulk Tagging (via API):**
We can provide a script if needed to bulk-tag applications.

### **Alternative: ServiceNow h_code Field:**

If H-codes are already in ServiceNow CMDB:
- Platform can extract from ServiceNow `h_code` field
- Requires applications to be matched in CMDB
- Current CMDB match rate: 8.8% (38/431 apps)

### **How to Verify:**

System reports coverage automatically:
```
✅ Apps with H-code: 390/431 (90.5%)  ← Target achieved
⚠️  Apps without H-code: 41 (9.5%)
```

### **SOW Impact:**

Without H-code coverage:
- Chargeback reports show costs as "Unassigned"
- Cannot allocate costs to specific departments/business units
- SOW requirement not met: "H-code coverage >90%"

**Note:** This is a **data quality requirement**. The platform works without H-codes, but cannot perform department-level chargeback allocation.

---

## 4. ServiceNow Production Credentials

| Attribute | Details |
|-----------|---------|
| **Requirement** | OAuth credentials for PROD ServiceNow CMDB API |
| **Priority** | 🟡 HIGH (Enrichment) |
| **Owner** | PepsiCo ServiceNow Administrator |
| **Status** | ❌ Pending |
| **Estimated Time** | 15-30 minutes |

### **What's Needed:**

OAuth Client ID and Secret with read-only access to ServiceNow CMDB APIs in the production environment.

### **Current Status:**

- ✅ TEST environment credentials working
- ❌ PROD environment credentials not provided
- Current enrichment rate (TEST): 8.8%

### **Required Information:**

1. **ServiceNow Instance URL**
   - Format: `https://<instance>.service-now.com`
   - Example: `https://pepsicodev2.service-now.com` (TEST - need PROD)

2. **OAuth Client ID**
   - Must have CMDB read permissions

3. **OAuth Client Secret**
   - For OAuth 2.0 client credentials flow

### **Required API Permissions:**

- `READ` on `cmdb_ci_appl` (Applications)
- `READ` on `cmdb_ci_server` (Servers)
- `READ` on `cmdb_rel_ci` (Relationships)

### **How to Create OAuth Client:**

1. Log into ServiceNow as administrator
2. Navigate to: **System OAuth → Application Registry**
3. Create new OAuth API endpoint for client credentials
4. Grant read-only access to CMDB tables
5. Generate Client ID and Secret
6. Provide credentials securely

### **How to Verify:**

```bash
# Test connectivity (we'll provide script)
curl -X POST "https://<instance>.service-now.com/oauth_token.do" \
  -d "grant_type=client_credentials" \
  -d "client_id=<client_id>" \
  -d "client_secret=<client_secret>"
```

Expected: HTTP 200 with access token

### **SOW Impact:**

Without ServiceNow enrichment:
- No application owner information
- No sector/business unit mapping
- Limited server relationship data
- **Can still meet basic SOW requirements** (optional for basic license reporting)

---

## Requirement Summary Table

| Requirement | Priority | Status | Estimated Effort | Blocking? |
|-------------|----------|--------|------------------|-----------|
| Licensing API Permissions | 🔴 CRITICAL | ❌ Pending | 5-10 min/controller | ✅ YES |
| Licensing API v1 Availability | 🔴 CRITICAL | ❌ Pending | 1-3 days (support) | ⚠️ Has fallback |
| H-Code Tags (>90%) | 🟡 HIGH | ❌ 0% | Ongoing | ✅ YES (data quality) |
| ServiceNow PROD Credentials | 🟡 HIGH | ❌ Pending | 15-30 minutes | ⚠️ Optional |

---

## Timeline for Go-Live

### **Week 1: Critical Items**
- [ ] Grant Licensing API permissions (Controllers 2 & 3)
- [ ] Contact AppDynamics support for API v1 availability
- [ ] Begin H-code tagging campaign

### **Week 2: Validation**
- [ ] Run test scripts to verify API access
- [ ] Validate H-code coverage increasing
- [ ] Provide ServiceNow PROD credentials

### **Week 3: Production Deployment**
- [ ] Final validation of all requirements
- [ ] Production ETL execution
- [ ] Dashboard review with stakeholders
- [ ] Go-live

---

## Support & Documentation

### **Test Scripts Provided:**

1. `test_all_prod_controllers.sh` - Comprehensive test of all controllers
2. `test_prod_licensing_api.sh` - Single controller detailed test
3. `test_licensing_api_quick.sh` - Standalone version for sharing

### **Documentation Provided:**

1. `LICENSING_API_MANUAL_TEST_GUIDE.md` - Step-by-step API testing
2. `APPDYNAMICS_LICENSE_API_RESEARCH.md` - Complete API research findings
3. `DEPLOYMENT_GUIDE.md` - Production deployment instructions

### **Contact:**

For questions or assistance with any requirement, contact the CDW implementation team.

---

**Document Version:** 1.0
**Last Updated:** 2025-11-21
