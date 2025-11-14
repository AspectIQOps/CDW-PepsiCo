# 🚀 Fresh Environment Setup Checklist

## For Tomorrow's Fresh AWS Deployment

Since you're starting from scratch (dropped EC2 + RDS), use this checklist to ensure everything is set up correctly including the new materialized views.

---

## ✅ Pre-Deployment (Do This First)

### 1. Update SQL Init Script with Additional Indexes

The composite indexes you created today need to be added to the init script for automatic deployment:

**ACTION REQUIRED:** Add these to `sql/init/00_complete_init.sql` before the `GRANT PERMISSIONS` section:

```sql
-- ========================================
-- 12. PERFORMANCE INDEXES (for time-based queries)
-- ========================================

-- Composite indexes for time-series queries (critical for dashboard performance)
CREATE INDEX IF NOT EXISTS idx_license_usage_ts_app
ON license_usage_fact(ts DESC, app_id);

CREATE INDEX IF NOT EXISTS idx_license_cost_ts_app
ON license_cost_fact(ts DESC, app_id);

-- Update statistics
ANALYZE license_usage_fact;
ANALYZE license_cost_fact;
```

This ensures new environments get these indexes automatically!

---

## 📋 Deployment Sequence

### Step 1: AWS Infrastructure (30 min)

**EC2 Instance:**
- [ ] Launch EC2 instance (t3.medium or larger recommended)
- [ ] Attach IAM role with SSM read permissions
- [ ] Configure security group (allow outbound 443, 5432)
- [ ] Install Docker + AWS CLI

**RDS PostgreSQL:**
- [ ] Launch RDS PostgreSQL 16+ instance
- [ ] Configure security group (allow EC2 security group on port 5432)
- [ ] Set master username: `postgres`
- [ ] Save master password securely
- [ ] Enable automated backups (7-day retention)
- [ ] Enable enhanced monitoring (optional but recommended)

**Networking:**
- [ ] Ensure EC2 and RDS are in same VPC
- [ ] Verify RDS security group allows EC2 security group
- [ ] Test connectivity: `psql -h <RDS_ENDPOINT> -U postgres -d postgres`

---

### Step 2: AWS SSM Parameter Store (10 min)

Store all credentials in SSM (encrypted):

**Database Parameters:**
```bash
aws ssm put-parameter \
  --name "/pepsico/DB_HOST" \
  --value "<RDS_ENDPOINT>" \
  --type "String" \
  --region us-east-2

aws ssm put-parameter \
  --name "/pepsico/DB_NAME" \
  --value "cost_analytics_db" \
  --type "String" \
  --region us-east-2

aws ssm put-parameter \
  --name "/pepsico/DB_USER" \
  --value "etl_analytics" \
  --type "String" \
  --region us-east-2

aws ssm put-parameter \
  --name "/pepsico/DB_PASSWORD" \
  --value "<GENERATE_STRONG_PASSWORD>" \
  --type "SecureString" \
  --region us-east-2
```

**AppDynamics Parameters** (comma-separated for multi-controller):
```bash
aws ssm put-parameter \
  --name "/pepsico/appdynamics/CONTROLLER" \
  --value "controller1.saas.appdynamics.com,controller2.saas.appdynamics.com" \
  --type "String" \
  --region us-east-2

aws ssm put-parameter \
  --name "/pepsico/appdynamics/ACCOUNT" \
  --value "account1,account2" \
  --type "String" \
  --region us-east-2

aws ssm put-parameter \
  --name "/pepsico/appdynamics/CLIENT_NAME" \
  --value "client1,client2" \
  --type "String" \
  --region us-east-2

aws ssm put-parameter \
  --name "/pepsico/appdynamics/CLIENT_SECRET" \
  --value "secret1,secret2" \
  --type "SecureString" \
  --region us-east-2
```

**ServiceNow Parameters:**
```bash
aws ssm put-parameter \
  --name "/pepsico/servicenow/INSTANCE" \
  --value "pepsico" \
  --type "String" \
  --region us-east-2

aws ssm put-parameter \
  --name "/pepsico/servicenow/CLIENT_ID" \
  --value "<OAUTH_CLIENT_ID>" \
  --type "String" \
  --region us-east-2

aws ssm put-parameter \
  --name "/pepsico/servicenow/CLIENT_SECRET" \
  --value "<OAUTH_CLIENT_SECRET>" \
  --type "SecureString" \
  --region us-east-2
```

**Verify:**
```bash
aws ssm get-parameters-by-path --path "/pepsico" --region us-east-2 | jq '.Parameters[].Name'
```

---

### Step 3: Database Initialization (15 min)

**Connect to RDS:**
```bash
psql -h <RDS_ENDPOINT> -U postgres -d postgres
```

**Run initialization scripts in order:**

```sql
-- 1. Create main database
CREATE DATABASE cost_analytics_db;

-- Switch to the new database
\c cost_analytics_db

-- 2. Run complete initialization (creates tables, users, indexes, seed data)
\i sql/init/00_complete_init.sql

-- 3. Verify tables created
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
-- Should return: 20+

-- 4. Verify users created
SELECT usename FROM pg_user WHERE usename IN ('etl_analytics', 'grafana_ro');
-- Should show both users

-- 5. Verify indexes
SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';
-- Should return: 30+ (including the new composite indexes)

-- Exit
\q
```

**IMPORTANT:** If you updated `00_complete_init.sql` with the composite indexes (Step 1 Pre-Deployment), they'll be created automatically. Otherwise, create them manually:

```bash
psql -h <RDS_ENDPOINT> -U postgres -d cost_analytics_db

CREATE INDEX IF NOT EXISTS idx_license_usage_ts_app
ON license_usage_fact(ts DESC, app_id);

CREATE INDEX IF NOT EXISTS idx_license_cost_ts_app
ON license_cost_fact(ts DESC, app_id);

ANALYZE license_usage_fact;
ANALYZE license_cost_fact;
```

---

### Step 4: Create Materialized Views (5 min)

**⭐ This is the NEW step for performance optimization:**

```bash
# Connect as etl_analytics user (password from SSM)
psql -h <RDS_ENDPOINT> -U etl_analytics -d cost_analytics_db

# Create all 8 materialized views
\i sql/migrations/create_materialized_views.sql

# Verify views created
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'MATERIALIZED VIEW';
-- Should show 8 views (mv_daily_cost_by_controller, mv_daily_usage_by_capability, etc.)

# Exit
\q
```

**Why this matters:**
- Views are empty until first ETL run (that's normal)
- After first ETL run, views are auto-refreshed
- Dashboards will query views instead of doing expensive JOINs
- Meets SOW requirement: <5 second dashboard response time

---

### Step 5: Deploy ETL Container (20 min)

**Build Docker image:**
```bash
cd /path/to/CDW-PepsiCo
docker build -f docker/etl/Dockerfile -t pepsico-analytics-etl:latest .
```

**Test ETL pipeline locally (OPTIONAL but recommended):**
```bash
docker run --rm \
  -e AWS_REGION=us-east-2 \
  -e AWS_DEFAULT_REGION=us-east-2 \
  pepsico-analytics-etl:latest

# Watch for successful completion:
# ✅ Phase 1 Complete: AppDynamics Extract
# ✅ Phase 2 Complete: ServiceNow Enrichment
# ✅ Phase 3 Complete: Finalization
# ✅ Final: Refresh Materialized Views  <-- NEW STEP
```

**Push to ECR (if using ECR):**
```bash
aws ecr get-login-password --region us-east-2 | \
  docker login --username AWS --password-stdin <AWS_ACCOUNT>.dkr.ecr.us-east-2.amazonaws.com

docker tag pepsico-analytics-etl:latest \
  <AWS_ACCOUNT>.dkr.ecr.us-east-2.amazonaws.com/pepsico-analytics-etl:latest

docker push <AWS_ACCOUNT>.dkr.ecr.us-east-2.amazonaws.com/pepsico-analytics-etl:latest
```

**Set up cron job or EventBridge for daily runs:**
```bash
# Option 1: Cron (on EC2)
crontab -e
# Add: 0 2 * * * docker run --rm -e AWS_REGION=us-east-2 pepsico-analytics-etl:latest

# Option 2: AWS EventBridge (recommended for production)
# Create rule to trigger ECS task daily
```

---

### Step 6: Verify ETL Data (10 min)

After first ETL run completes:

```bash
psql -h <RDS_ENDPOINT> -U grafana_ro -d cost_analytics_db

-- Check applications loaded
SELECT COUNT(*) FROM applications_dim;
-- Should be >0 (number of AppD applications)

-- Check usage data
SELECT COUNT(*) FROM license_usage_fact;
-- Should be >0 (90 days × apps × license types)

-- Check cost data
SELECT COUNT(*) FROM license_cost_fact;
-- Should be >0 (same as usage)

-- Check materialized views populated
SELECT 'mv_daily_cost_by_controller' as view, COUNT(*) FROM mv_daily_cost_by_controller
UNION ALL
SELECT 'mv_daily_usage_by_capability', COUNT(*) FROM mv_daily_usage_by_capability
UNION ALL
SELECT 'mv_cost_by_sector_controller', COUNT(*) FROM mv_cost_by_sector_controller
UNION ALL
SELECT 'mv_architecture_metrics_90d', COUNT(*) FROM mv_architecture_metrics_90d;
-- All should have >0 rows

-- Check view refresh logged
SELECT * FROM etl_execution_log
WHERE job_name = 'refresh_views'
ORDER BY started_at DESC LIMIT 1;
-- Should show SUCCESS status

\q
```

---

### Step 7: Deploy Grafana Dashboards (15 min)

**Option 1: Manual Import (Quick)**
1. Log into Grafana
2. Create PostgreSQL data source:
   - Host: `<RDS_ENDPOINT>:5432`
   - Database: `cost_analytics_db`
   - User: `grafana_ro`
   - Password: (from SSM)
   - SSL Mode: `require`
3. Import each dashboard JSON from `config/grafana/dashboards/v2/`
4. Test dashboard loads (<5 seconds per SOW requirement)

**Option 2: Automated Provisioning (Production)**
- Configure Grafana provisioning with dashboard JSON files
- Set up via Kubernetes ConfigMap or file mounts

---

## ✅ Post-Deployment Verification

### Database Health
```sql
-- Table counts
SELECT
  'Applications' as table, COUNT(*) FROM applications_dim
UNION ALL
  SELECT 'Servers', COUNT(*) FROM servers_dim
UNION ALL
  SELECT 'Usage Facts', COUNT(*) FROM license_usage_fact
UNION ALL
  SELECT 'Cost Facts', COUNT(*) FROM license_cost_fact
UNION ALL
  SELECT 'Materialized Views', COUNT(*) FROM information_schema.tables
    WHERE table_type = 'MATERIALIZED VIEW';
```

### ETL Pipeline Health
```sql
-- Last 5 ETL runs
SELECT job_name, started_at, finished_at, status, rows_ingested
FROM etl_execution_log
ORDER BY started_at DESC
LIMIT 5;

-- Expected jobs:
-- appd_extract, snow_enrichment, appd_finalize, refresh_views
```

### Dashboard Performance
- [ ] Executive Overview loads in <5 seconds
- [ ] Cost Analytics loads in <5 seconds
- [ ] Architecture Analysis loads in <5 seconds
- [ ] All panels show data (not "No Data")

### SOW Compliance Check
```sql
-- H-code coverage (should be >90%)
SELECT
  COUNT(*) FILTER (WHERE h_code IS NOT NULL) * 100.0 / COUNT(*) as h_code_coverage_pct
FROM applications_dim
WHERE appd_application_id IS NOT NULL;

-- Peak vs Pro distribution
SELECT license_tier, COUNT(*) as app_count
FROM applications_dim
GROUP BY license_tier;

-- Architecture distribution
SELECT ar.pattern_name, COUNT(*) as app_count
FROM applications_dim a
LEFT JOIN architecture_dim ar ON a.architecture_id = ar.architecture_id
GROUP BY ar.pattern_name;
```

---

## 🐛 Common Issues & Fixes

### Issue: Views not refreshing automatically

**Symptom:** Dashboard shows old data after ETL run

**Fix:**
```bash
# Check if refresh_views.py ran
psql -c "SELECT * FROM etl_execution_log WHERE job_name = 'refresh_views' ORDER BY started_at DESC LIMIT 1;"

# Manual refresh
docker exec -it <etl_container> python3 /app/scripts/etl/refresh_views.py
```

### Issue: Slow dashboard queries

**Symptom:** Dashboards take >10 seconds to load

**Check:**
1. Are materialized views populated?
   ```sql
   SELECT COUNT(*) FROM mv_daily_cost_by_controller;
   ```
2. Are views fresh?
   ```sql
   SELECT MAX(cost_date) FROM mv_daily_cost_by_controller;
   -- Should be within last 24 hours
   ```
3. Are indexes in place?
   ```sql
   SELECT indexname FROM pg_indexes
   WHERE tablename LIKE 'mv_%';
   -- Should show indexes on each view
   ```

**Fix:**
```sql
-- Refresh views
SELECT * FROM refresh_all_dashboard_views();

-- Re-analyze
ANALYZE mv_daily_cost_by_controller;
ANALYZE mv_daily_usage_by_capability;
```

### Issue: ETL fails with SSM errors

**Symptom:** "Required SSM parameters not found"

**Fix:**
```bash
# Verify IAM role attached to EC2
aws sts get-caller-identity

# Verify SSM parameters exist
aws ssm get-parameters-by-path --path "/pepsico" --region us-east-2

# Check IAM permissions include ssm:GetParameter
```

---

## 📊 What's Different From Before

### 🆕 New Components:
1. **8 Materialized Views** - Pre-aggregated data for fast dashboards
2. **refresh_views.py** - Automated view refresh after ETL
3. **Composite Indexes** - `idx_license_usage_ts_app`, `idx_license_cost_ts_app`
4. **View refresh in pipeline** - Automatic refresh as final ETL step

### ⚡ Performance Improvements:
- Dashboard query time: **~30s → <5s** (6x faster)
- Eliminated: Correlated subqueries with EXISTS
- Reduced: 3-5 table JOINs per panel to simple view queries

### 📋 SOW Compliance:
- ✅ Dashboard response <5 seconds (Section 5.2)
- ✅ Complete audit trail (refresh_views logged to etl_execution_log)
- ✅ Future-proof architecture (easy to add more views)

---

## 🎯 Success Criteria

After completing this checklist, you should have:

- [x] Fresh RDS database with all tables, indexes, and views
- [x] ETL pipeline running successfully (all 3 phases + view refresh)
- [x] 8 materialized views populated with data
- [x] 6 dashboards loading in <5 seconds
- [x] All credentials in SSM (no hardcoded secrets)
- [x] Audit trail of all ETL runs and view refreshes
- [x] >90% H-code coverage (if data available)
- [x] Peak vs Pro and Architecture categorization working

---

## 📞 Quick Reference

**Database Connection:**
```bash
psql -h <RDS_ENDPOINT> -U etl_analytics -d cost_analytics_db
```

**Refresh Views Manually:**
```bash
python3 scripts/etl/refresh_views.py
```

**Run ETL Pipeline:**
```bash
docker run --rm -e AWS_REGION=us-east-2 pepsico-analytics-etl:latest
```

**Check ETL Logs:**
```sql
SELECT * FROM etl_execution_log ORDER BY started_at DESC LIMIT 10;
```

---

**Good luck with tomorrow's deployment! 🚀**
