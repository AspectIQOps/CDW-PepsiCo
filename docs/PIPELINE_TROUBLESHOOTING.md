# Pipeline Troubleshooting Guide

**Quick Reference for Common Pipeline Issues**

---

## 🔍 **Is the Pipeline Stuck?**

### **On EC2 Instance:**

```bash
# 1. Run the status checker
./scripts/utils/check_pipeline_status.sh

# 2. Check if Python process is still alive
ps aux | grep python

# 3. Check CPU usage (should be >0% if working)
top

# 4. Check database activity
# Look for long-running queries
```

---

## ⏱️ **Expected Runtime**

### **Normal Pipeline Duration:**

| Deployment Size | Applications | Mock Data Generation | Total ETL Time |
|-----------------|--------------|----------------------|----------------|
| Small | <50 apps | 1-2 minutes | 2-5 minutes |
| Medium | 50-200 apps | 3-8 minutes | 5-15 minutes |
| Large | 200+ apps | 10-20 minutes | 15-30 minutes |

### **What Takes Time:**

1. **Mock Data Generation (if API unavailable):**
   - 12 months × apps × 2 capabilities (APM + MRUM)
   - Example: 128 apps × 365 days × 2 = ~93,440 records
   - Bulk insert with ON CONFLICT: 2-5 minutes

2. **Cost Calculation:**
   - JOIN between usage and price tables
   - Same number of records as usage
   - Usually 1-2 minutes

3. **ServiceNow Enrichment:**
   - API calls for each application
   - Can be slow if SNOW API is slow
   - 3-10 minutes depending on apps

4. **Materialized View Refresh:**
   - Rebuilding 8 aggregated views
   - Usually <2 minutes

---

## 🚨 **Common Issues**

### **1. Pipeline Appears Frozen**

**Symptoms:**
- No output for >5 minutes
- CPU at 0%
- No database activity

**Likely Causes:**
- ❌ Network timeout waiting for API response
- ❌ Database deadlock
- ❌ Out of memory

**Solutions:**
```bash
# Check for database locks
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  SELECT pid, state, query_start, query
  FROM pg_stat_activity
  WHERE state = 'active';"

# Check memory usage
free -h

# Kill and restart if truly stuck
pkill -f "python.*run_pipeline"
python3 scripts/etl/run_pipeline.py
```

---

### **2. Mock Data Generation Taking Forever**

**Symptoms:**
- Stuck on "Generating mock usage data"
- Progress bar not moving
- High CPU usage

**Likely Causes:**
- ❌ Too many applications (200+)
- ❌ Database insert performance

**Solutions:**
```bash
# Check how many apps are being processed
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  SELECT COUNT(*) FROM applications_dim;"

# Check if data is being inserted
watch -n 5 "psql -h $DB_HOST -U $DB_USER -d $DB_NAME -t -c 'SELECT COUNT(*) FROM license_usage_fact'"

# If stuck, check database indexes exist
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  SELECT tablename, indexname
  FROM pg_indexes
  WHERE tablename IN ('license_usage_fact', 'license_cost_fact');"
```

**Expected Behavior:**
- Mock data generates ~365 days × apps count
- Bulk insert should take 2-10 minutes max
- If >15 minutes, something is wrong

---

### **3. Database Connection Timeout**

**Symptoms:**
```
Error: could not connect to server
psycopg2.OperationalError: timeout expired
```

**Solutions:**
```bash
# Check database is running
sudo systemctl status postgresql

# Check connection parameters
echo "DB_HOST=$DB_HOST"
echo "DB_NAME=$DB_NAME"
echo "DB_USER=$DB_USER"

# Test connection manually
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT version();"

# Check RDS security group (if using AWS RDS)
# Ensure EC2 instance security group is allowed
```

---

### **4. AppDynamics API Timeout**

**Symptoms:**
```
HTTPSConnectionPool: Max retries exceeded
Connection timeout
```

**Solutions:**
```bash
# Test connectivity to AppD controller
curl -v https://pepsi-test.saas.appdynamics.com/controller/

# Check if mock fallback is working
# Should see: "WARNING: USING MOCK DATA GENERATION (DEMO MODE)"

# Verify environment variables
echo "APPD_CONTROLLERS=$APPD_CONTROLLERS"
echo "APPD_ACCOUNTS=$APPD_ACCOUNTS"

# If repeated timeouts, increase timeout in code
# Or run with fewer controllers
```

---

### **5. Out of Memory**

**Symptoms:**
```
MemoryError
Killed
Process terminated
```

**Solutions:**
```bash
# Check available memory
free -h

# Check swap space
swapon --show

# Reduce batch size in appd_extract.py
# Or run controllers one at a time:
export APPD_CONTROLLERS="pepsi-test.saas.appdynamics.com"
python3 scripts/etl/appd_extract.py
```

---

## 📊 **Monitoring Pipeline Progress**

### **Real-Time Monitoring:**

```bash
# Terminal 1: Watch table growth
watch -n 5 "psql -h $DB_HOST -U $DB_USER -d $DB_NAME -t -c '
  SELECT
    (SELECT COUNT(*) FROM applications_dim) AS apps,
    (SELECT COUNT(*) FROM license_usage_fact) AS usage,
    (SELECT COUNT(*) FROM license_cost_fact) AS costs,
    (SELECT COUNT(*) FROM chargeback_fact) AS chargeback
'"

# Terminal 2: Watch database activity
watch -n 3 "psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c '
  SELECT state, COUNT(*)
  FROM pg_stat_activity
  GROUP BY state
'"

# Terminal 3: Watch process CPU/Memory
top -p $(pgrep -f "python.*run_pipeline")
```

---

## 🔧 **Manual Pipeline Steps (If Stuck)**

If the full pipeline is stuck, you can run phases individually:

```bash
# Phase 1: AppDynamics Extract
python3 scripts/etl/appd_extract.py

# Phase 2: ServiceNow Enrichment (optional)
python3 scripts/etl/snow_enrichment.py

# Phase 3: Finalize
python3 scripts/etl/appd_finalize.py

# Phase 4: Chargeback
python3 scripts/etl/chargeback_calculation.py

# Phase 5: Refresh Views
python3 scripts/etl/refresh_views.py
```

---

## 🐛 **Debug Mode**

### **Enable Verbose Logging:**

```bash
# Add to Python scripts or run with:
export DEBUG=1
python3 scripts/etl/run_pipeline.py

# Or edit appd_extract.py and add:
import logging
logging.basicConfig(level=logging.DEBUG)
```

---

## 📝 **Checking Logs**

### **Where to Look:**

```bash
# Check stdout/stderr from running process
ps aux | grep python  # Get PID
tail -f /proc/<PID>/fd/1  # stdout
tail -f /proc/<PID>/fd/2  # stderr

# Check system logs
sudo journalctl -u etl-pipeline -f

# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-*.log

# Check application logs
tail -f /var/log/etl/*.log
```

---

## ⚡ **Quick Fixes**

### **Pipeline hung? Force restart:**
```bash
pkill -9 -f "python.*run_pipeline"
python3 scripts/etl/run_pipeline.py
```

### **Database stuck? Kill queries:**
```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE state = 'active'
  AND query NOT LIKE '%pg_stat_activity%'
  AND now() - query_start > interval '10 minutes';"
```

### **Start fresh? Clear data:**
```bash
# ⚠️  WARNING: This deletes all ETL data
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  TRUNCATE TABLE license_usage_fact CASCADE;
  TRUNCATE TABLE license_cost_fact CASCADE;
  TRUNCATE TABLE chargeback_fact CASCADE;
  TRUNCATE TABLE applications_dim CASCADE;
"
```

---

## 📞 **Still Stuck?**

### **Information to Gather:**

1. **Pipeline output:**
   ```bash
   # Last 50 lines of output
   ps aux | grep python  # Get PID
   tail -50 /proc/<PID>/fd/1
   ```

2. **Database state:**
   ```bash
   ./scripts/utils/check_pipeline_status.sh > status.txt
   ```

3. **Environment:**
   ```bash
   # Save environment config (redact secrets!)
   env | grep -E "DB_|APPD_|SN_" > env.txt
   ```

4. **Resource usage:**
   ```bash
   free -h > resources.txt
   df -h >> resources.txt
   top -b -n 1 >> resources.txt
   ```

---

## ✅ **Success Indicators**

### **Pipeline Completed Successfully When:**

```bash
# Check final output shows:
✅ Phase 1: AppDynamics Core Data Extract - COMPLETE
✅ Phase 2: ServiceNow Enrichment - COMPLETE
✅ Phase 3: Cost Calculations - COMPLETE
✅ Phase 4: Chargeback Calculation - COMPLETE
✅ Phase 5: Materialized View Refresh - COMPLETE

# Verify data exists:
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  SELECT
    (SELECT COUNT(*) FROM applications_dim) AS apps,
    (SELECT COUNT(*) FROM license_usage_fact) AS usage,
    (SELECT COUNT(*) FROM license_cost_fact) AS costs
"

# Should see:
# apps: >0 (your application count)
# usage: >0 (apps × ~365 days × 2)
# costs: >0 (same as usage)
```

---

**Last Updated:** 2025-11-21
