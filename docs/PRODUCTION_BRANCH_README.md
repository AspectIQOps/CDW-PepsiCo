# Production API-Only Branch

**Branch:** `production-api-only`
**Purpose:** Production deployment with real AppDynamics Licensing API integration
**Status:** Ready for deployment once client requirements are met

---

## Overview

This branch contains the **production-ready version** of the PepsiCo AppDynamics Analytics Platform with:

✅ **Real API integration only** - No mock data generation
✅ **Fail-fast error handling** - Pipeline terminates immediately if API unavailable
✅ **Clear error messages** - Detailed troubleshooting guidance
✅ **Clean codebase** - Obsolete files archived

---

## Key Differences from Demo Branch

| Feature | production-api-only (this branch) | deploy-docker (demo branch) |
|---------|-----------------------------------|------------------------------|
| Mock data fallback | ❌ Removed | ✅ Available |
| API failure behavior | ❌ Terminates with error | ⚠️ Falls back to mock data |
| Production ready | ✅ Yes | ⚠️ Demo only |
| Error messages | ✅ Detailed troubleshooting | ⚠️ Generic warnings |

---

## Prerequisites for Production Deployment

Before deploying this branch to production, the client MUST provide:

### **Critical Blockers:**

1. **AppDynamics Licensing API Permissions**
   - Grant "License Admin" role to OAuth clients
   - Required on: `pepsico-prod`, `pepsicoeu-prod`
   - See: `docs/CLIENT_REQUIREMENTS_DETAILED.md`

2. **AppDynamics Licensing API v1 Availability**
   - Verify API v1 is enabled on PROD controllers
   - May require AppDynamics Support ticket
   - See: `docs/LICENSING_API_MANUAL_TEST_GUIDE.md`

3. **H-Code Tags (>90% coverage)**
   - Tag applications with H-codes in AppDynamics
   - Target: >90% of applications
   - See: `docs/CLIENT_REQUIREMENTS_DETAILED.md`

4. **ServiceNow Production Credentials**
   - OAuth Client ID & Secret for PROD CMDB
   - See: `docs/CLIENT_REQUIREMENTS_DETAILED.md`

---

## Testing Before Deployment

### **1. Verify API Access:**

```bash
# Test all PROD controllers
./scripts/utils/test_all_prod_controllers.sh

# Expected output: ✅ PASS for all controllers
```

### **2. Test Single Controller:**

```bash
# Test one controller with detailed output
./scripts/utils/test_prod_licensing_api.sh

# Expected output: HTTP 200 on both API endpoints
```

### **3. Verify Environment Variables:**

```bash
# Check credentials are loaded
echo $APPD_CONTROLLERS
echo $APPD_ACCOUNTS
echo $APPD_ACCOUNT_IDS
echo $DB_HOST
echo $SN_INSTANCE
```

---

## Deployment Steps

### **1. Deploy Infrastructure:**

```bash
# Start PostgreSQL database
docker-compose up -d postgres

# Wait for database to be ready
sleep 10

# Verify connection
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT version();"
```

### **2. Initialize Database:**

```bash
# Run schema initialization
./scripts/setup/init_database.sh
```

### **3. Run ETL Pipeline:**

```bash
# Execute full pipeline
python3 scripts/etl/run_pipeline.py

# Monitor for errors
# If License API unavailable, will see:
# ❌ CRITICAL ERROR: AppDynamics Licensing API Unavailable
```

### **4. Verify Data:**

```bash
# Check data was loaded
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  SELECT
    (SELECT COUNT(*) FROM applications_dim) AS apps,
    (SELECT COUNT(*) FROM license_usage_fact) AS usage,
    (SELECT COUNT(*) FROM license_cost_fact) AS costs
"
```

Expected output:
```
 apps | usage  | costs
------+--------+--------
  431 | 550818 | 550818
```

---

## Error Handling

### **If Pipeline Fails with "Licensing API Unavailable":**

**Error Message:**
```
❌ CRITICAL ERROR: AppDynamics Licensing API Unavailable
ETL pipeline terminated. Cannot proceed without real license data.
```

**Troubleshooting:**

1. **Check API Permissions:**
   ```bash
   ./scripts/utils/test_all_prod_controllers.sh
   ```

2. **Verify API Availability:**
   - Run manual test: `./scripts/utils/test_prod_licensing_api.sh`
   - Check for HTTP 500 errors
   - Contact AppDynamics Support if needed

3. **Review Documentation:**
   - `docs/CLIENT_REQUIREMENTS_DETAILED.md`
   - `docs/PIPELINE_TROUBLESHOOTING.md`
   - `docs/LICENSING_API_MANUAL_TEST_GUIDE.md`

---

## Files Removed from This Branch

The following files were archived (moved to `/archive`) as they're not needed for production:

- Mock data generation functions
- Demo-specific scripts (`populate_demo_data.py`)
- Duplicate/obsolete test scripts
- Old dashboard versions

See `docs/FILE_AUDIT_AND_CLEANUP.md` for complete list.

---

## Client Requirements Documentation

**Quick Reference:**
- `docs/CLIENT_REQUIREMENTS_CHECKLIST.md` - Quick checklist

**Detailed:**
- `docs/CLIENT_REQUIREMENTS_DETAILED.md` - Full technical details

**For Management:**
- `docs/CLIENT_REQUIREMENTS_EXECUTIVE_SUMMARY.md` - Executive summary

---

## Switching Between Branches

### **To Use Demo Branch (with mock data fallback):**

```bash
git checkout deploy-docker
# Pipeline will use mock data if API unavailable
```

### **To Use Production Branch (API-only):**

```bash
git checkout production-api-only
# Pipeline will fail fast if API unavailable
```

---

## Production Checklist

Before go-live, verify:

- [ ] All 4 client requirements provided (see docs)
- [ ] Test scripts pass on all PROD controllers
- [ ] Database initialized with correct schema
- [ ] Environment variables loaded
- [ ] ETL pipeline runs successfully
- [ ] Dashboards populate with data
- [ ] H-code coverage >90%
- [ ] ServiceNow enrichment working

---

## Support

**Documentation:**
- Deployment: `docs/DEPLOYMENT_GUIDE.md`
- Troubleshooting: `docs/PIPELINE_TROUBLESHOOTING.md`
- SOW Compliance: `docs/SOW_COMPLIANCE_FINAL.txt`

**Test Scripts:**
- `scripts/utils/test_all_prod_controllers.sh`
- `scripts/utils/test_prod_licensing_api.sh`
- `scripts/utils/diagnose_container_crash.sh`
- `scripts/utils/check_pipeline_status.sh`

---

**Last Updated:** 2025-11-21
**Status:** ✅ Ready for production deployment
