# Deployment Guide - PepsiCo Analytics Platform

## Overview
This guide ensures all components (including materialized views) are properly deployed in new environments.

---

## 🚀 Quick Start (New Environment Setup)

### 1. Database Initialization

Run the complete initialization script:

```bash
# Connect to PostgreSQL
psql -h <DB_HOST> -U postgres -d postgres

# Create database and initialize schema
\i sql/init/00_complete_init.sql
```

**This creates:**
- Users: `etl_analytics`, `grafana_ro`
- All dimension tables (applications, sectors, owners, etc.)
- All fact tables (usage, costs, chargeback, forecasts)
- Audit tables (etl_execution_log, data_lineage, etc.)
- Indexes on fact and dimension tables
- Seed data (capabilities, architecture types, pricing)

### 2. Create Materialized Views (Dashboard Performance)

After database initialization, create the materialized views:

```bash
# Connect as etl_analytics user
psql -h <DB_HOST> -U etl_analytics -d cost_analytics_db

# Create all materialized views
\i sql/migrations/create_materialized_views.sql
```

**This creates 8 materialized views:**
- `mv_daily_cost_by_controller` - Daily cost aggregations (eliminates correlated subqueries)
- `mv_daily_usage_by_capability` - Daily usage by license type
- `mv_cost_by_sector_controller` - Cost rollups by business sector
- `mv_cost_by_owner_controller` - Cost rollups by application owner
- `mv_architecture_metrics_90d` - Architecture efficiency analysis
- `mv_app_cost_rankings_monthly` - Top applications by cost
- `mv_monthly_chargeback_summary` - Executive chargeback reporting
- `mv_peak_pro_comparison` - Peak vs Pro tier comparison

**Why materialized views?**
- SOW Requirement: Dashboard response time <5 seconds (Section 5.2)
- Eliminates expensive JOINs on every dashboard load
- Pre-aggregates common query patterns identified from actual dashboard analysis
- Supports 6 existing dashboards + 2 future dashboards

### 3. Apply Additional Migrations (if needed)

```bash
# Apply controller field migration (if upgrading existing environment)
\i sql/migrations/add_controller_field.sql
```

### 4. Create Additional Performance Indexes

These indexes were created during testing and should be included in new environments:

```bash
psql -h <DB_HOST> -U etl_analytics -d cost_analytics_db

-- Composite indexes for time-based queries (critical for performance)
CREATE INDEX IF NOT EXISTS idx_license_usage_ts_app
ON license_usage_fact(ts DESC, app_id);

CREATE INDEX IF NOT EXISTS idx_license_cost_ts_app
ON license_cost_fact(ts DESC, app_id);

-- Update statistics for query planner
ANALYZE license_usage_fact;
ANALYZE license_cost_fact;
```

---

## 📦 Docker Deployment

### Build and Deploy ETL Container

```bash
cd docker/etl
docker build -t pepsico-analytics-etl:latest .
docker push <YOUR_ECR_REPO>/pepsico-analytics-etl:latest
```

### Environment Variables (via AWS SSM)

Store these in AWS SSM Parameter Store:

**Database:**
- `/pepsico/DB_HOST`
- `/pepsico/DB_NAME`
- `/pepsico/DB_USER`
- `/pepsico/DB_PASSWORD`

**AppDynamics:**
- `/pepsico/appdynamics/CONTROLLER` (comma-separated for multi-controller)
- `/pepsico/appdynamics/ACCOUNT` (comma-separated account names)
- `/pepsico/appdynamics/ACCOUNT_ID` (comma-separated numeric account IDs - **OPTIONAL**, can be auto-discovered)
- `/pepsico/appdynamics/CLIENT_NAME` (comma-separated)
- `/pepsico/appdynamics/CLIENT_SECRET` (comma-separated, encrypted)

**How to Get ACCOUNT_ID:**
1. **Option 1 (Recommended):** Leave blank - will be auto-discovered and saved to SSM automatically
   - First ETL run: Discovers via API call to `/controller/api/accounts/myaccount`
   - Saves to SSM: `/pepsico/appdynamics/ACCOUNT_ID` (comma-separated, matches controller order)
   - Future ETL runs: Uses saved value from SSM (no redundant API calls)
   - Requires IAM permission: `ssm:PutParameter` (otherwise re-discovers each run)
2. **Option 2:** Customer provides: Login to AppD → Settings → License → "Account ID"
3. **Multi-controller example:**
   ```bash
   # 2 controllers = 2 account IDs (comma-separated, in order)
   APPD_ACCOUNT_IDS="12345,67890"
   ```

**ServiceNow:**
- `/pepsico/servicenow/INSTANCE`
- `/pepsico/servicenow/CLIENT_ID` (OAuth 2.0)
- `/pepsico/servicenow/CLIENT_SECRET` (OAuth 2.0, encrypted)

---

## ✅ Verifying Real vs Mock Data

**IMPORTANT:** All mock/synthetic data generation has been **completely removed** from production ETL scripts. The system ONLY pulls real license usage data from AppDynamics Licensing API.

### How to Verify You're Getting Real Data

**1. Check ETL Output Logs**

When running the ETL pipeline, look for these messages:
```
✅ Auto-discovered Account ID: 12345  (if not provided in env vars)
✅ Fetched license usage data from AppDynamics API
✅ Inserted X usage records from AppDynamics API
```

**If the API is unavailable, the ETL will FAIL:**
```
❌ CRITICAL: AppDynamics Licensing API is unavailable
   Cannot proceed without real license usage data
   Please verify:
   - Account ID is correct: 12345
   - Controller URL is accessible: https://...
   - OAuth credentials are valid
   - Network connectivity to AppDynamics
```

**No fallback to estimated/synthetic data** - the pipeline fails gracefully and logs the error.

**2. Verify Environment Variables (Optional)**

AppDynamics account IDs are **optional** - they will be auto-discovered if not provided:
```bash
# Check if APPD_ACCOUNT_IDS is set (optional)
echo $APPD_ACCOUNT_IDS

# If empty or not set, the ETL will auto-discover it
# If set, should be comma-separated numeric account IDs:
# Example: "12345,67890"
```

**3. Query the Database**

Check for usage data with timestamps matching real AppDynamics data:
```sql
-- Check recent usage data
SELECT
    ts,
    COUNT(*) as records,
    SUM(units_consumed) as total_units
FROM license_usage_fact
WHERE ts >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY ts
ORDER BY ts DESC;

-- If you see consistent daily records with realistic unit counts,
-- you're getting real data
```

**4. Compare with AppDynamics UI**

Log into your AppDynamics controller and compare:
- License usage numbers in AppD UI
- Usage numbers in your dashboards
- They should match closely (within normal variance)

### Mock Data Scripts (Demo/Testing Only)

The following scripts generate synthetic data for **demo and testing purposes only**:
- [scripts/utils/populate_demo_data.py](../scripts/utils/populate_demo_data.py) - DO NOT run in production

These are **not** part of the production ETL pipeline and should only be used in isolated test environments.

---

## 🔄 ETL Pipeline Execution Order

The pipeline automatically runs in this order:

1. **Phase 1: AppDynamics Extract** (`appd_extract.py`)
   - Fetches REAL license usage data via AppDynamics Licensing API (`/controller/licensing/usage/account/{accountId}`)
   - Fetches application metadata from AppDynamics controllers
   - Extracts H-code from AppD tags
   - Determines Peak vs Pro tier from API response
   - Classifies Monolith vs Microservices architecture
   - **Note:** ETL terminates if Licensing API is unavailable - real data is required

2. **Phase 2: ServiceNow Enrichment** (`snow_enrichment.py`)
   - Targeted CMDB lookups (only for AppD apps)
   - Enriches with sector, owner, support group
   - Maps application-server relationships

3. **Phase 3: Finalization** (`appd_finalize.py`)
   - Generates chargeback records
   - Creates forecasts
   - Runs allocation engine

4. **Optional: Advanced Forecasting** (`advanced_forecasting.py`)
   - Multiple forecast algorithms (linear, exponential, seasonal)
   - Confidence intervals
   - Scenario planning

5. **Optional: Cost Allocation** (`allocation_engine.py`)
   - Distributes shared service costs
   - Applies allocation rules

6. **Final: Refresh Materialized Views** (`refresh_views.py`) ⭐ **NEW**
   - Updates all 8 materialized views
   - Uses CONCURRENT refresh (zero downtime)
   - Updates query planner statistics
   - Logs to audit table

### Manual View Refresh

If needed, refresh views manually:

```bash
# Inside Docker container
python3 /app/scripts/etl/refresh_views.py

# Or via psql
psql -h <DB_HOST> -U etl_analytics -d cost_analytics_db
SELECT * FROM refresh_all_dashboard_views();
```

---

## 📊 Dashboard Deployment (Grafana)

### Import Dashboards

All enhanced v2 dashboards are in: `config/grafana/dashboards/v2/`

**Available Dashboards:**
1. ✅ Executive Overview (Enhanced).json
2. ✅ Usage by License Type (Enhanced).json
3. ✅ Cost Analytics (Enhanced).json
4. ✅ Peak vs Pro Analysis (Enhanced).json
5. ✅ Architecture Analysis (Enhanced).json
6. ✅ Admin Panel (Enhanced).json
7. ⏳ Trends & Forecasts (Enhanced).json - *To be created*
8. ⏳ Allocation & Chargeback (Enhanced).json - *To be created*

### Dashboard Data Source

Configure Grafana PostgreSQL data source:
- **Host:** Same as DB_HOST
- **Database:** cost_analytics_db
- **User:** grafana_ro (read-only)
- **SSL Mode:** require (for production)

---

## ✅ Verification Checklist

After deployment, verify:

### Database Schema
```sql
-- Check table count (should be 20+)
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

-- Check materialized view count (should be 8)
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'MATERIALIZED VIEW';

-- Check index count (should be 35+)
SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';
```

### Materialized Views
```sql
-- Check view row counts (should be >0 after first ETL run)
SELECT table_name,
       (xpath('/row/cnt/text()',
        xml_count))[1]::text::int as row_count
FROM (
  SELECT table_name,
         query_to_xml(format('SELECT COUNT(*) AS cnt FROM %I', table_name),
                      false, true, '') AS xml_count
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_type = 'MATERIALIZED VIEW'
) t
ORDER BY table_name;
```

### ETL Pipeline
```bash
# Run full pipeline
docker run --rm \
  -e AWS_REGION=us-east-2 \
  pepsico-analytics-etl:latest

# Check logs for view refresh
tail -f /var/log/etl_pipeline.log | grep "Refresh"
```

### Dashboard Performance
- Test dashboard load time (should be <5 seconds per SOW requirement)
- Check Grafana query inspector for execution time
- Verify queries are hitting materialized views, not base tables

---

## 🔧 Troubleshooting

### Views Not Refreshing

**Problem:** Materialized views are stale

**Solution:**
```bash
# Manual refresh
python3 /app/scripts/etl/refresh_views.py

# Or via SQL
SELECT * FROM refresh_all_dashboard_views();
```

### Slow Dashboard Queries

**Problem:** Queries still slow despite views

**Check:**
1. Are views being used? (Check Grafana query inspector)
2. Are views up to date? (Check row counts)
3. Are indexes in place? (Run index verification query above)

**Fix:**
```sql
-- Force re-analyze for better query plans
ANALYZE mv_daily_cost_by_controller;
ANALYZE mv_daily_usage_by_capability;
-- ... repeat for all views
```

### Views Missing After Database Restore

**Problem:** Restored from backup but views don't exist

**Solution:**
```bash
# Recreate views
psql -h <DB_HOST> -U etl_analytics -d cost_analytics_db \
  -f sql/migrations/create_materialized_views.sql

# Refresh views
python3 /app/scripts/etl/refresh_views.py
```

---

## 📅 Maintenance Schedule

### Daily (Automated via ETL Pipeline)
- ✅ Run full ETL pipeline (appd_extract → snow_enrichment → appd_finalize)
- ✅ Refresh materialized views (via refresh_views.py)
- ✅ Update query planner statistics (ANALYZE)

### Weekly (Manual)
- Check view row counts for anomalies
- Review ETL execution log for failures
- Monitor dashboard query performance

### Monthly (Manual)
- Review and optimize slow queries
- Consider adding new views if new query patterns emerge
- Validate H-code coverage (>90% per SOW requirement)

---

## 🎯 Success Criteria (SOW Compliance)

After deployment, verify these SOW requirements:

- ✅ **Dashboard Response Time:** <5 seconds (Section 5.2)
- ✅ **Data Accuracy:** ±2% cost attribution (Section 1.4)
- ✅ **Coverage:** 100% application ownership mapping (Section 1.4)
- ✅ **H-code Coverage:** >90% populated (Section 3.4)
- ✅ **Audit Trail:** ETL execution logged (Section 2.5.3)
- ✅ **Peak vs Pro:** Tier differentiation operational (Section 5.1)
- ✅ **Architecture:** Monolith vs Microservices categorized (Section 5.1)

---

## 📞 Support

For issues or questions:
1. Check ETL execution logs: `SELECT * FROM etl_execution_log ORDER BY started_at DESC LIMIT 10;`
2. Check view refresh logs: `SELECT * FROM etl_execution_log WHERE job_name = 'refresh_views' ORDER BY started_at DESC LIMIT 10;`
3. Review architecture documentation in `docs/`
