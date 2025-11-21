# Repository File Audit & Cleanup Recommendations

**Date:** 2025-11-21
**Branch:** production-api-only
**Purpose:** Identify obsolete files for archival

---

## Files to Archive (Move to /archive)

### **Duplicate/Copy Files:**
| File | Reason | Action |
|------|--------|--------|
| `README-1.md` | Duplicate of README.md | Archive |
| `config/grafana/dashboards/final copy/` (entire directory) | Duplicate of final/ | Archive |
| `scripts/etl/appd_extract_2.py` | Backup of appd_extract.py | Archive |
| `scripts/etl/run_pipeline copy.py` | Duplicate of run_pipeline.py | Archive |
| `scripts/utils/test_all_controllers copy.sh` | Duplicate of test_all_controllers.sh | Archive |
| `scripts/utils/test_licensing_api_quick copy.sh` | Duplicate of test_licensing_api_quick.sh | Archive |

### **Superseded Test Scripts:**
| File | Reason | Action |
|------|--------|--------|
| `scripts/utils/AppDynamics API Diagnostic Script.sh` | Superseded by test_all_controllers.sh | Archive |
| `scripts/utils/manual_license_api_test.sh` | Superseded by test_licensing_api_quick.sh | Archive |
| `scripts/utils/test_license_api.py` | Replaced by shell-based tests | Archive |
| `scripts/utils/test_license_api_with_ssm.sh` | Superseded by test_all_controllers.sh | Archive |

### **Demo/Development Scripts (Not for Production):**
| File | Reason | Action |
|------|--------|--------|
| `scripts/utils/populate_demo_data.py` | Demo data generator (not needed in production-api-only) | Archive |
| `scripts/utils/validate_pipeline.py` | Development testing script | Keep (useful for validation) |

---

## Files to KEEP (Required for Production)

### **Core ETL Scripts:**
- ✅ `scripts/etl/appd_extract.py` - Phase 1: AppDynamics data extraction
- ✅ `scripts/etl/snow_enrichment.py` - Phase 2: ServiceNow enrichment
- ✅ `scripts/etl/appd_finalize.py` - Phase 3: Cost calculations
- ✅ `scripts/etl/chargeback_calculation.py` - Phase 4: Chargeback aggregation
- ✅ `scripts/etl/allocation_engine.py` - Phase 5: Shared service allocation
- ✅ `scripts/etl/advanced_forecasting.py` - Phase 6: Forecasting
- ✅ `scripts/etl/refresh_views.py` - Phase 7: Materialized view refresh
- ✅ `scripts/etl/run_pipeline.py` - Main orchestrator
- ✅ `scripts/etl/reconciliation_engine.py` - AppD/SNOW reconciliation

### **Production Test Scripts:**
- ✅ `scripts/utils/test_all_prod_controllers.sh` - Test PROD controllers
- ✅ `scripts/utils/test_prod_licensing_api.sh` - Test single PROD controller
- ✅ `scripts/utils/test_licensing_api_quick.sh` - Standalone verbose test (for sharing)
- ✅ `scripts/utils/test_all_controllers.sh` - Test all controllers (TEST/PROD)
- ✅ `scripts/utils/test_all_controllers_standalone.sh` - Standalone version

### **Utilities:**
- ✅ `scripts/utils/discover_appd_account_ids.py` - Account ID discovery
- ✅ `scripts/utils/discover_with_ssm.sh` - Discover and save to SSM
- ✅ `scripts/utils/check_pipeline_status.sh` - Monitor running pipeline
- ✅ `scripts/utils/diagnose_container_crash.sh` - Debug crashed containers
- ✅ `scripts/utils/platform_manager.sh` - Docker platform management
- ✅ `scripts/utils/ec2_initial_setup.sh` - EC2 environment setup
- ✅ `scripts/utils/validate_pipeline.py` - Pipeline validation

### **Setup Scripts:**
- ✅ `scripts/setup/init_database.sh` - Database initialization

### **Database:**
- ✅ `sql/init/00_complete_init.sql` - Full schema
- ✅ `sql/init/01_performance_views.sql` - Materialized views

### **Configuration:**
- ✅ `config/grafana/dashboards/final/` - All 8 production dashboards
- ✅ `docker/etl/entrypoint.sh` - Docker entrypoint

### **Documentation (Current):**
- ✅ `README.md` - Main repository README
- ✅ `docs/DEPLOYMENT_GUIDE.md` - Production deployment guide
- ✅ `docs/SOW_COMPLIANCE_FINAL.txt` - SOW compliance verification
- ✅ `docs/APPDYNAMICS_LICENSE_API_RESEARCH.md` - API research findings
- ✅ `docs/LICENSING_API_MANUAL_TEST_GUIDE.md` - API testing guide
- ✅ `docs/FRESH_ENVIRONMENT_CHECKLIST.md` - Environment setup checklist
- ✅ `docs/PIPELINE_TROUBLESHOOTING.md` - Troubleshooting guide
- ✅ `requirements.txt` - Python dependencies

### **Documentation (Demo-Specific - Keep for Reference):**
- ⚠️ `docs/DEMO_READINESS_PLAN.md` - Demo strategy (keep for reference)
- ⚠️ `docs/DEMO_PIPELINE_STATUS.md` - Demo status (keep for reference)
- ⚠️ `docs/FINAL_DELIVERY_STATUS.md` - Delivery status snapshot

### **Future Enhancements:**
- ✅ `future_enhancements/` - Future feature ideas (keep)

---

## Recommended Actions

### **Immediate (Today):**

```bash
# Move duplicate files to archive
mv "./README-1.md" "./archive/"
mv "./config/grafana/dashboards/final copy" "./archive/dashboards_final_copy"
mv "./scripts/etl/appd_extract_2.py" "./archive/"
mv "./scripts/etl/run_pipeline copy.py" "./archive/"
mv "./scripts/utils/test_all_controllers copy.sh" "./archive/"
mv "./scripts/utils/test_licensing_api_quick copy.sh" "./archive/"

# Move superseded test scripts
mv "./scripts/utils/AppDynamics API Diagnostic Script.sh" "./archive/"
mv "./scripts/utils/manual_license_api_test.sh" "./archive/"
mv "./scripts/utils/test_license_api.py" "./archive/"
mv "./scripts/utils/test_license_api_with_ssm.sh" "./archive/"

# Move demo data generator (production-api-only branch doesn't need it)
mv "./scripts/utils/populate_demo_data.py" "./archive/"
```

**Total files to archive:** 14 files/directories

---

## Files Already in Archive (Good)

- ✅ `archive/v1/` - Original dashboard versions
- ✅ `archive/v2/` - Dashboard v2
- ✅ `archive/v3/` - Dashboard v3
- ✅ `archive/add_controller_field.sql` - Old migration
- ✅ `archive/check_views.sh` - Old utility
- ✅ `archive/dashboard_diagnostics.sh` - Old diagnostic
- ✅ `archive/ec2_minimal_setup.sh` - Old setup script
- ✅ `docs/archive/current status 11-12-25.md` - Old status doc

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
| Files to archive | 14 | Move to /archive |
| Core production files | 50+ | Keep |
| Already archived | 30+ | No action |

**Repository will be cleaner and more maintainable after archival.**

---

## Notes for Production Branch

This cleanup is specifically for the `production-api-only` branch. The `deploy-docker` branch (with mock data fallback) may want to keep:
- `populate_demo_data.py` - For demo purposes
- Demo documentation - For reference

