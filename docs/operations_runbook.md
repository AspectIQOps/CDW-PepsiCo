# PepsiCo AppDynamics License Management
## Operations Runbook v1.0

**Last Updated:** October 30, 2025  
**System:** AppDynamics License Tracking & Chargeback  
**Support Team:** CDW Data Engineering / PepsiCo IT Operations  
**On-Call Rotation:** TBD

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Daily Operations](#daily-operations)
3. [Weekly Operations](#weekly-operations)
4. [Monthly Operations](#monthly-operations)
5. [Common Tasks](#common-tasks)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Emergency Procedures](#emergency-procedures)
8. [Monitoring & Alerts](#monitoring--alerts)
9. [Contact Information](#contact-information)

---

## System Overview

### Purpose
Automated ETL pipeline that extracts AppDynamics license usage and ServiceNow CMDB data, calculates costs, performs reconciliation, generates forecasts, and produces monthly chargebacks.

### Key Components
- **PostgreSQL Database**: Data warehouse (appd_licensing)
- **ETL Pipeline**: Python scripts orchestrated by entrypoint.sh
- **Grafana Dashboards**: 8 tabs for visualization and reporting
- **AWS SSM**: Secrets management

### Normal Operating Schedule
- **Daily ETL**: 2:00 AM ET (automated via scheduler)
- **Monthly Chargeback Close**: 5th of each month
- **Forecast Refresh**: 1st of each month
- **Database Backup**: Daily at 3:00 AM ET

### SLA Targets
- ETL completion: <30 minutes
- Dashboard response time: <5 seconds
- Match rate: >95% for AppD-monitored apps
- Cost accuracy: ±2% variance

---

## Daily Operations

### Morning Health Check (15 minutes)

**Schedule:** 8:00 AM ET daily

#### Step 1: Verify ETL Success

```bash
# Check last ETL run status
docker-compose exec postgres psql -U etl_analytics -d appd_licensing -c "
SELECT 
    job_name,
    started_at,
    finished_at,
    status,
    rows_ingested,
    error_message
FROM etl_execution_log
ORDER BY started_at DESC
LIMIT 5;
"
```

**Expected Output:**
```
 job_name  |       started_at        |       finished_at       | status  | rows_ingested
-----------+-------------------------+-------------------------+---------+---------------
 appd_etl  | 2025-10-30 02:00:15     | 2025-10-30 02:05:42     | success | 1092
```

**Action if Failed:**
- Check error_message column
- Review ETL logs: `docker-compose logs etl`
- Follow troubleshooting guide (Section 6)
- Notify on-call engineer if unable to resolve

---

#### Step 2: Validate Data Quality

```bash
# Run validation script
docker-compose run --rm etl python3 /app/scripts/utils/validate_pipeline.py
```

**Expected Output:**
```
✅ Validation Complete!
🎉 ALL CHECKS PASSED - Pipeline is healthy!
```

**Key Metrics to Review:**
- Table row counts (ensure growth)
- Match rate (should be 100% for AppD apps)
- Cost accuracy variance (<2%)
- No orphaned records

**Action if Warnings:**
- Review specific failed check
- Determine if issue is critical or informational
- Log issue in tracking system
- Escalate if data quality is compromised

---

#### Step 3: Check Dashboard Availability

```bash
# Test Grafana endpoint
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health

# Expected: 200
```

**If Grafana is Down:**
```bash
# Check container status
docker-compose ps grafana

# Restart if needed
docker-compose restart grafana

# Check logs
docker-compose logs --tail=50 grafana
```

---

#### Step 4: Review Reconciliation Results

```bash
# Check reconciliation match rate
docker-compose exec postgres psql -U etl_analytics -d appd_licensing -c "
SELECT 
    COUNT(*) FILTER (WHERE appd_application_id IS NOT NULL AND sn_sys_id IS NOT NULL) as matched,
    COUNT(*) FILTER (WHERE appd_application_id IS NOT NULL AND sn_sys_id IS NULL) as appd_only,
    COUNT(*) FILTER (WHERE appd_application_id IS NULL AND sn_sys_id IS NOT NULL) as snow_only,
    COUNT(*) as total
FROM applications_dim;
"
```

**Expected:**
- Matched apps should be ~100% of AppD-monitored apps
- AppD-only count should be 0 (all matched)
- ServiceNow-only represents unmonitored apps (expected)

**Action if Match Rate Drops:**
- Check for new applications in AppD or ServiceNow
- Review `reconciliation_log` for low-confidence matches
- Add manual mappings if needed (see Section 5.4)

---

### End of Day Summary (5 minutes)

**Schedule:** 5:00 PM ET daily

```bash
# Quick status check
docker-compose exec postgres psql -U etl_analytics -d appd_licensing -c "
SELECT 
    'Last ETL Run' as metric,
    MAX(finished_at)::text as value
FROM etl_execution_log
WHERE status = 'success'
UNION ALL
SELECT 
    'Total Applications',
    COUNT(*)::text
FROM applications_dim
UNION ALL
SELECT
    'Today Usage Records',
    COUNT(*)::text
FROM license_usage_fact
WHERE ts::date = CURRENT_DATE;
"
```

**Action Required:**
- Document any issues encountered
- Update tracking system with resolution notes
- Prepare handoff notes for next shift (if 24/7 ops)

---

## Weekly Operations

### Monday: Database Maintenance (30 minutes)

**Schedule:** Monday 6:00 AM ET

```bash
# Connect to database
docker-compose exec postgres psql -U etl_analytics -d appd_licensing

-- Vacuum and analyze all tables
VACUUM ANALYZE;

-- Check database size
SELECT 
    pg_size_pretty(pg_database_size('appd_licensing')) as db_size,
    pg_size_pretty(pg_total_relation_size('license_usage_fact')) as usage_fact_size,
    pg_size_pretty(pg_total_relation_size('license_cost_fact')) as cost_fact_size;

-- Check for bloat (tables > 20% bloat need attention)
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    n_dead_tup,
    ROUND(100 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

**Action if High Bloat:**
```sql
-- Reclaim space (requires table lock)
VACUUM FULL ANALYZE table_name;

-- Or schedule during maintenance window
```

---

### Wednesday: Performance Review (45 minutes)

**Schedule:** Wednesday 10:00 AM ET

#### Check Slow Queries

```sql
-- Enable pg_stat_statements if not already
-- (should be configured in postgresql.conf)

-- Top 10 slowest queries
SELECT 
    LEFT(query, 60) as query_preview,
    calls,
    ROUND(total_exec_time::numeric / 1000, 2) as total_seconds,
    ROUND(mean_exec_time::numeric, 2) as avg_ms,
    ROUND(max_exec_time::numeric, 2) as max_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

**Action if Slow Queries Found:**
- Review query execution plans with `EXPLAIN ANALYZE`
- Check if indexes are being used
- Consider adding indexes or rewriting queries
- Update dashboard panels if Grafana queries are slow

---

#### Review Index Usage

```sql
-- Unused indexes (candidates for removal)
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexname NOT LIKE '%_pkey';

-- Missing indexes (tables with high sequential scans)
SELECT 
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    ROUND(100 * seq_scan / NULLIF(seq_scan + idx_scan, 0), 2) as seq_scan_pct
FROM pg_stat_user_tables
WHERE seq_scan > 1000
ORDER BY seq_scan DESC;
```

---

### Friday: Backup Verification (20 minutes)

**Schedule:** Friday 9:00 AM ET

```bash
# Check last backup timestamp
ls -lh /backup/appd_licensing_*.dump | tail -5

# Verify backup size (should be consistent with database size)
du -h /backup/appd_licensing_$(date +%Y%m%d).dump

# Test restore to temp database (monthly, not weekly)
# This is a longer process, schedule for first Friday of month
```

**Backup Retention Check:**
```bash
# Ensure 30 days of backups are retained
find /backup -name "appd_licensing_*.dump" -mtime +30 -delete

# Upload to S3 for long-term retention
aws s3 sync /backup/ s3://pepsico-appd-backups/database/ \
  --exclude "*" --include "appd_licensing_*.dump"
```

---

## Monthly Operations

### 1st of Month: Forecast Refresh (15 minutes)

**Schedule:** 1st of month, 8:00 AM ET

```bash
# Manually trigger forecast generation
docker-compose run --rm etl python3 /app/scripts/etl/advanced_forecasting.py
```

**Verify Forecasts:**
```sql
-- Check forecast coverage
SELECT 
    COUNT(DISTINCT app_id) as forecasted_apps,
    MIN(month_start) as earliest_forecast,
    MAX(month_start) as latest_forecast,
    COUNT(*) as total_forecast_records
FROM forecast_fact
WHERE month_start > CURRENT_DATE;
```

**Expected:**
- Forecasts for next 12 months
- All AppD-monitored apps have forecasts
- Confidence intervals populated

---

### 5th of Month: Chargeback Finalization (60 minutes)

**Schedule:** 5th of month, 10:00 AM ET

#### Step 1: Review Chargeback Data

```sql
-- Current month chargebacks
SELECT 
    s.sector_name,
    COUNT(DISTINCT cf.app_id) as app_count,
    SUM(cf.usd_amount) as total_chargeback,
    COUNT(*) FILTER (WHERE cf.chargeback_cycle LIKE 'allocated%') as allocated_count
FROM chargeback_fact cf
JOIN sectors_dim s ON s.sector_id = cf.sector_id
WHERE cf.month_start = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
GROUP BY s.sector_name
ORDER BY total_chargeback DESC;
```

#### Step 2: Export Chargeback Report

```bash
# Generate CSV export for finance team
docker-compose exec postgres psql -U etl_analytics -d appd_licensing -c "
COPY (
    SELECT 
        cf.month_start,
        s.sector_name,
        o.owner_name,
        COALESCE(ad.appd_application_name, ad.sn_service_name) as application,
        ad.h_code,
        cf.usd_amount,
        cf.chargeback_cycle
    FROM chargeback_fact cf
    JOIN applications_dim ad ON ad.app_id = cf.app_id
    JOIN sectors_dim s ON s.sector_id = cf.sector_id
    JOIN owners_dim o ON o.owner_id = cf.owner_id
    WHERE cf.month_start = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
    ORDER BY s.sector_name, cf.usd_amount DESC
) TO STDOUT WITH CSV HEADER;
" > chargeback_report_$(date +%Y%m).csv
```

#### Step 3: Finalize Chargebacks

```sql
-- Mark chargebacks as finalized (prevents further updates)
UPDATE chargeback_fact
SET is_finalized = TRUE
WHERE month_start = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
  AND is_finalized = FALSE;
```

#### Step 4: Send Report to Finance

```bash
# Email report to finance team
# (This would be automated via SendGrid, SES, or internal email system)
echo "Monthly chargeback report attached" | \
  mail -s "AppDynamics License Chargeback - $(date +%B %Y)" \
       -a chargeback_report_$(date +%Y%m).csv \
       finance-team@pepsico.com
```

---

### Mid-Month: Capacity Planning Review (30 minutes)

**Schedule:** 15th of month, 2:00 PM ET

```sql
-- Review usage trends
WITH monthly_usage AS (
    SELECT 
        DATE_TRUNC('month', ts) as month,
        SUM(units_consumed) as total_units,
        SUM(usd_cost) as total_cost
    FROM license_usage_fact luf
    JOIN license_cost_fact lcf USING (ts, app_id, capability_id, tier)
    WHERE ts >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY DATE_TRUNC('month', ts)
)
SELECT 
    TO_CHAR(month, 'YYYY-MM') as month,
    ROUND(total_units, 2) as units,
    ROUND(total_cost, 2) as cost,
    ROUND(100 * (total_units - LAG(total_units) OVER (ORDER BY month)) / 
          NULLIF(LAG(total_units) OVER (ORDER BY month), 0), 2) as growth_pct
FROM monthly_usage
ORDER BY month DESC;
```

**Action if High Growth:**
- Review new applications added
- Check for usage anomalies
- Forecast budget impact
- Notify stakeholders of projected overages

---

## Common Tasks

### 5.1: Trigger Manual ETL Run

**When:** On-demand (e.g., after data correction, testing)

```bash
# Full pipeline
docker-compose run --rm etl

# Individual components
docker-compose run --rm etl_snow   # ServiceNow only
docker-compose run --rm etl_appd   # AppDynamics only
```

**Post-Run Verification:**
- Check `etl_execution_log` for success status
- Run validation script
- Review dashboard for updated data

---

### 5.2: Refresh Materialized Views

**When:** After manual data updates, performance issues

```bash
docker-compose exec postgres psql -U etl_analytics -d appd_licensing << EOF
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_cost_summary;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_app_cost_current;
SELECT 'Materialized views refreshed successfully' as status;
EOF
```

**Note:** `CONCURRENTLY` requires unique indexes and doesn't lock tables

---

### 5.3: Update Pricing Configuration

**When:** Contract renewal, rate changes

```sql
-- Add new pricing rule
INSERT INTO price_config (capability_id, tier, start_date, end_date, unit_rate)
VALUES (
    (SELECT capability_id FROM capabilities_dim WHERE capability_code = 'APM'),
    'PEAK',
    '2026-01-01',
    NULL,  -- Open-ended (current pricing)
    1.35   -- New rate
);

-- Close out old pricing rule
UPDATE price_config
SET end_date = '2025-12-31'
WHERE capability_id = (SELECT capability_id FROM capabilities_dim WHERE capability_code = 'APM')
  AND tier = 'PEAK'
  AND end_date IS NULL
  AND price_id != (SELECT MAX(price_id) FROM price_config);  -- Don't close the one we just added
```

**Verification:**
```sql
-- Ensure no overlapping date ranges
SELECT 
    cd.capability_code,
    tier,
    start_date,
    COALESCE(end_date::text, 'ongoing') as end_date,
    unit_rate
FROM price_config pc
JOIN capabilities_dim cd ON cd.capability_id = pc.capability_id
WHERE capability_code = 'APM' AND tier = 'PEAK'
ORDER BY start_date DESC;
```

---

### 5.4: Manual Application Mapping

**When:** Automatic reconciliation fails (score <80%)

#### Step 1: Identify Unmapped Applications

```sql
-- Find applications needing manual mapping
SELECT 
    rl.match_key_a as appd_name,
    rl.match_key_b as snow_name,
    rl.confidence_score
FROM reconciliation_log rl
WHERE match_status = 'needs_review'
ORDER BY confidence_score DESC;
```

#### Step 2: Add Manual Override

```sql
-- Example: Map "Supply Chain App" (AppD) to "Supply Chain System" (SNOW)
INSERT INTO mapping_overrides (
    source_system,
    source_key,
    target_table,
    target_field,
    override_value,
    updated_by
) VALUES (
    'AppDynamics',
    'Supply Chain App',
    'applications_dim',
    'sn_sys_id',
    'abc123def456',  -- ServiceNow sys_id
    'john.smith@pepsico.com'
);
```

#### Step 3: Re-run Reconciliation

```bash
docker-compose run --rm etl python3 /app/scripts/etl/reconciliation_engine.py
```

---

### 5.5: Database Backup & Restore

#### Manual Backup

```bash
# Full database backup
docker-compose exec postgres pg_dump \
  -U etl_analytics \
  -d appd_licensing \
  --format=custom \
  --compress=9 \
  --file=/tmp/manual_backup_$(date +%Y%m%d_%H%M%S).dump

# Copy backup out of container
docker cp pepsico-postgres:/tmp/manual_backup_*.dump ./backups/
```

#### Restore from Backup

```bash
# WARNING: This will overwrite the database!

# 1. Stop ETL jobs
docker-compose stop etl

# 2. Drop and recreate database
docker-compose exec postgres psql -U postgres -c "
DROP DATABASE IF EXISTS appd_licensing_restore_test;
CREATE DATABASE appd_licensing_restore_test;
"

# 3. Restore backup
docker-compose exec postgres pg_restore \
  -U etl_analytics \
  -d appd_licensing_restore_test \
  --verbose \
  /tmp/manual_backup_20251030_120000.dump

# 4. Verify restore
docker-compose exec postgres psql -U etl_analytics -d appd_licensing_restore_test -c "
SELECT COUNT(*) as total_apps FROM applications_dim;
"

# 5. If verified, rename databases (during maintenance window)
# docker-compose exec postgres psql -U postgres -c "
# ALTER DATABASE appd_licensing RENAME TO appd_licensing_old;
# ALTER DATABASE appd_licensing_restore_test RENAME TO appd_licensing;
# "
```

---

## Troubleshooting Guide

### Issue: ETL Job Failed

**Symptoms:**
- `etl_execution_log` shows status = 'failed'
- Error message in log
- Dashboard shows stale data

**Diagnosis:**

```bash
# Check ETL logs
docker-compose logs --tail=100 etl

# Check last error
docker-compose exec postgres psql -U etl_analytics -d appd_licensing -c "
SELECT error_message FROM etl_execution_log WHERE status = 'failed' ORDER BY started_at DESC LIMIT 1;
"
```

**Common Causes & Solutions:**

| Error Message | Cause | Solution |
|---------------|-------|----------|
| "Connection refused" | Database not ready | Wait 10s, retry. Check `docker-compose ps` |
| "Authentication failed" | Wrong credentials | Verify SSM parameters or .env file |
| "ModuleNotFoundError" | Missing Python dependency | Rebuild Docker image: `docker-compose build --no-cache etl` |
| "UNIQUE constraint violation" | Duplicate data | Check for concurrent ETL runs, review unique constraints |
| "HTTP 401 Unauthorized" | API credentials expired | Update AppD/ServiceNow credentials in SSM |
| "HTTP 429 Too Many Requests" | Rate limit exceeded | Wait 60s, retry with backoff |

**Resolution Steps:**
1. Fix root cause (update credentials, fix query, etc.)
2. Manually trigger ETL: `docker-compose run --rm etl`
3. Verify success in `etl_execution_log`
4. Run validation script
5. Document issue in tracking system

---

### Issue: Low Match Rate (<95%)

**Symptoms:**
- Reconciliation report shows match rate below target
- Many AppD apps show as "AppD Only"

**Diagnosis:**

```sql
-- Find unmatched AppD applications
SELECT 
    appd_application_name,
    'No ServiceNow match' as issue
FROM applications_dim
WHERE appd_application_id IS NOT NULL
  AND sn_sys_id IS NULL;

-- Check recent reconciliation attempts
SELECT * FROM reconciliation_log
WHERE match_status IN ('needs_review', 'no_match')
ORDER BY match_run_ts DESC
LIMIT 20;
```

**Common Causes:**
- New applications not yet in ServiceNow CMDB
- Application name mismatch (different naming conventions)
- ServiceNow CI not marked as operational

**Resolution:**
1. Verify apps exist in ServiceNow:
   - Check ServiceNow CMDB manually
   - Confirm operational_status = 1
2. Add manual mappings (see Section 5.4)
3. Re-run reconciliation
4. If persistent, escalate to CMDB team

---

### Issue: Cost Calculation Variance >2%

**Symptoms:**
- Validation script reports accuracy warning
- Expected cost ≠ Actual cost

**Diagnosis:**

```sql
-- Calculate variance
WITH expected AS (
    SELECT SUM(units_consumed * pc.unit_rate) as expected_cost
    FROM license_usage_fact luf
    JOIN price_config pc ON pc.capability_id = luf.capability_id
        AND pc.tier = luf.tier
        AND luf.ts::date BETWEEN pc.start_date AND COALESCE(pc.end_date, luf.ts::date)
),
actual AS (
    SELECT SUM(usd_cost) as actual_cost
    FROM license_cost_fact
)
SELECT 
    ROUND(e.expected_cost, 2) as expected,
    ROUND(a.actual_cost, 2) as actual,
    ROUND(100 * ABS(a.actual_cost - e.expected_cost) / e.expected_cost, 2) as variance_pct
FROM expected e, actual a;

-- Find records with no pricing rule
SELECT COUNT(*) as orphaned_usage
FROM license_usage_fact luf
LEFT JOIN price_config pc ON pc.capability_id = luf.capability_id
    AND pc.tier = luf.tier
    AND luf.ts::date BETWEEN pc.start_date AND COALESCE(pc.end_date, luf.ts::date)
WHERE pc.price_id IS NULL;
```

**Common Causes:**
- Missing pricing rules for certain capability/tier combinations
- Date range gaps in price_config
- Rounding differences (should be minimal)

**Resolution:**
1. Add missing pricing rules
2. Fill date range gaps
3. Re-run cost calculation step:
   ```bash
   docker-compose run --rm etl python3 -c "
   from appd_etl import calculate_costs, get_conn
   conn = get_conn()
   calculate_costs(conn)
   conn.close()
   "
   ```

---

### Issue: Dashboard Panels Not Loading

**Symptoms:**
- Grafana shows "No data"
- Panels timeout or error
- Slow dashboard performance

**Diagnosis:**

```bash
# Check Grafana logs
docker-compose logs --tail=50 grafana

# Test PostgreSQL connection from Grafana
docker-compose exec grafana sh -c "
apk add postgresql-client
psql -h postgres -U etl_analytics -d appd_licensing -c 'SELECT 1;'
"
```

**Common Causes:**
- PostgreSQL datasource not configured
- Query syntax errors
- Slow queries (>5 seconds)
- Stale materialized views

**Resolution:**
1. Verify datasource configuration in Grafana
2. Test panel queries manually:
   ```sql
   -- Copy query from panel and run in psql
   docker-compose exec postgres psql -U etl_analytics -d appd_licensing
   ```
3. Refresh materialized views (Section 5.2)
4. Add indexes if queries are slow
5. Simplify complex queries

---

## Emergency Procedures

### Emergency Contact List

| Role | Name | Phone | Email | Escalation Level |
|------|------|-------|-------|------------------|
| Primary On-Call | TBD | xxx-xxx-xxxx | oncall@team.com | 1 |
| Backup On-Call | TBD | xxx-xxx-xxxx | backup@team.com | 1 |
| Database Admin | TBD | xxx-xxx-xxxx | dba@team.com | 2 |
| PepsiCo IT Manager | TBD | xxx-xxx-xxxx | manager@pepsico.com | 3 |

---

### P1: Database Corruption

**Symptoms:**
- PostgreSQL crashes repeatedly
- Data integrity errors
- Unrecoverable failures

**Immediate Actions:**
1. STOP all ETL jobs: `docker-compose stop etl`
2. Take snapshot of database volume
3. Notify DBA and management immediately
4. Restore from latest verified backup (Section 5.5)
5. Perform data integrity checks:
   ```sql
   -- Check for corruption
   SELECT * FROM pg_stat_database WHERE datname = 'appd_licensing';
   
   -- Verify table integrity
   VACUUM FULL ANALYZE VERBOSE;
   ```

---

### P2: Security Breach

**Symptoms:**
- Unauthorized access detected
- Suspicious queries in logs
- Credential compromise suspected

**Immediate Actions:**
1. ISOLATE: Stop all containers: `docker-compose down`
2. NOTIFY: Security team immediately
3. PRESERVE: Don't delete logs or evidence
4. ROTATE: Change all passwords/API keys in AWS SSM
5. AUDIT: Review access logs:
   ```sql
   SELECT * FROM user_actions ORDER BY action_ts DESC LIMIT 100;
   SELECT * FROM pg_stat_activity;
   ```

---

## Monitoring & Alerts

### Critical Alerts (Immediate Response)

| Alert | Threshold | Action |
|-------|-----------|--------|
| ETL job failed | Any failure | Investigate within 15 min |
| Database down | Unavailable >2 min | Restart, escalate if persistent |
| Disk space | >85% full | Clear logs, archive old data |
| Cost variance | >5% | Emergency review, halt finalization |

### Warning Alerts (Review within 4 hours)

| Alert | Threshold | Action |
|-------|-----------|--------|
| Match rate | <95% | Review reconciliation log |
| Slow queries | >10 seconds | Optimize queries |
| Data staleness | >36 hours | Check ETL schedule |
| Forecast gaps | Missing apps | Re-run forecasting |

---

## Contact Information

### Support Channels

**Slack:** #appd-licensing-support  
**Email:** appd-licensing-team@pepsico.com  
**Ticket System:** ServiceNow (Assignment Group: AppD License Ops)

### Vendor Support

**Grafana Support:** https://grafana.com/support  
**AWS Support:** Console → Support Center  
**PostgreSQL Community:** https://postgresql.org/support

---

**END OF OPERATIONS RUNBOOK**