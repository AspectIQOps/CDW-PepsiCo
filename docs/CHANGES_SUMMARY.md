# Changes Summary - Analytics Platform Rename

## Overview
Renamed from AppDynamics-specific to tool-agnostic analytics platform with extensibility framework.

---

## Naming Changes

| Component | Old Value | New Value |
|-----------|-----------|-----------|
| Database Name | `testdb` | `cost_analytics_db` |
| ETL User | `appd_ro` | `etl_analytics` |
| Grafana User | `grafana_ro` | `grafana_ro` (unchanged) |
| SSM Path | `/aspectiq/demo/` | `/pepsico/` |
| Container | `pepsico-etl-unified` | `pepsico-etl-analytics` |

---

## Files Updated

### ✅ SQL Schema Files (New Versions)

1. **`sql/init/00_create_users.sql`**
   - Creates `etl_analytics` user (was `appd_ro`)
   - Creates `grafana_ro` user (unchanged)
   - Grants to `cost_analytics_db` (was `testdb`)
   - Updated SSM references

2. **`sql/init/01_schema.sql`** ⭐ NEW TABLES ADDED
   - **NEW:** `tool_configurations` table for multi-tool support
   - **ENHANCED:** `audit_etl_runs` with `tool_name` column
   - All existing tables preserved
   - Tool-prefixed naming: `appd_*`, `servicenow_*`, `shared_*`
   - Ready for future tools: `elastic_*`, `datadog_*`, etc.

3. **`sql/init/02_seed_dimensions.sql`**
   - Need to review and update (you'll provide this)

4. **`sql/init/03_materialized_views.sql`**
   - Need to review and update (you'll provide this)

### ✅ Docker & Configuration Files

5. **`docker-compose.ec2.yaml`**
   - Updated SSM paths to `/pepsico/`
   - Environment variables use SSM exclusively
   - Container name: `pepsico-etl-analytics`
   - Mounts AWS credentials for SSM access

6. **`entrypoint.sh`**
   - Fetches ALL credentials from SSM (no .env fallback)
   - Updated paths: `/pepsico/DB_*`, `/pepsico/appdynamics/*`, `/pepsico/servicenow/*`
   - Tests database connection before starting ETL
   - Exports variables for Python scripts

### ✅ Python ETL Scripts

7. **All 6 Python scripts** (bulk rename already done this morning)
   - `scripts/etl/advanced_forecasting.py`
   - `scripts/etl/allocation_engine.py`
   - `scripts/etl/appd_etl.py`
   - `scripts/etl/audit_logger.py`
   - `scripts/etl/reconciliation_engine.py`
   - `scripts/etl/snow_etl.py`
   
   **Changes:**
   - Database name references updated
   - User name references updated
   - SSM path references updated
   - **TODO:** Add `tool_name` parameter to audit logging

### ✅ New Consolidated Script

8. **`scripts/utils/platform_manager.sh`** ⭐ NEW
   - Single script replaces 5 utilities
   - Commands: start, stop, restart, status, health, validate, logs, clean, db, ssm
   - Better error handling and color output
   - Comprehensive health checks

---

## New Extensibility Framework

### tool_configurations Table

```sql
CREATE TABLE tool_configurations (
    tool_id SERIAL PRIMARY KEY,
    tool_name VARCHAR(50) UNIQUE NOT NULL,      -- 'appdynamics', 'servicenow', 'elastic'
    display_name VARCHAR(100),                  -- 'AppDynamics'
    is_active BOOLEAN DEFAULT TRUE,             -- Enable/disable tool
    last_successful_run TIMESTAMP,              -- Track last run
    configuration JSONB,                        -- Tool-specific config
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**Purpose:**
- Track which tools are configured
- Enable/disable tools without code changes
- Store tool-specific configuration
- Monitor last successful run per tool
- Future: Drive ETL orchestration

**Initial Data:**
```sql
INSERT INTO tool_configurations (tool_name, display_name, is_active)
VALUES 
    ('appdynamics', 'AppDynamics', TRUE),
    ('servicenow', 'ServiceNow', TRUE);
```

### Enhanced audit_etl_runs Table

```sql
ALTER TABLE audit_etl_runs 
ADD COLUMN tool_name VARCHAR(50) NOT NULL;  -- Which tool this run was for

CREATE INDEX idx_audit_tool_time ON audit_etl_runs(tool_name, start_time DESC);
```

**Benefits:**
- Track ETL runs per tool
- Query performance by tool
- Identify tool-specific issues
- Generate per-tool reports

---

## SSM Parameter Structure

### New Path Structure

```
/pepsico/
├── DB_HOST                    # RDS endpoint
├── DB_NAME                    # cost_analytics_db
├── DB_USER                    # etl_analytics
├── DB_PASSWORD                # (SecureString)
├── DB_ADMIN_PASSWORD          # postgres master
├── GRAFANA_DB_PASSWORD        # grafana_ro password
│
├── appdynamics/
│   ├── CONTROLLER             # Controller URL
│   ├── ACCOUNT                # Account name
│   ├── CLIENT_ID              # API client ID
│   └── CLIENT_SECRET          # (SecureString)
│
├── servicenow/
│   ├── INSTANCE               # Instance URL
│   ├── USER                   # API username
│   └── PASS                   # (SecureString)
│
└── (ready for future tools)
    ├── elastic/
    ├── datadog/
    └── splunk/
```

### Migration Commands

If migrating from old SSM paths:

```bash
# List old parameters
aws ssm get-parameters-by-path --path /aspectiq/demo --region us-east-2

# Copy to new path (manual for each)
OLD_VALUE=$(aws ssm get-parameter --name /aspectiq/demo/DB_HOST --region us-east-2 --query 'Parameter.Value' --output text)
aws ssm put-parameter --name /pepsico/DB_HOST --value "$OLD_VALUE" --type String --region us-east-2
```

---

## Scripts Deprecated

These scripts are replaced by `platform_manager.sh`:

| Old Script | New Command |
|------------|-------------|
| `daily_startup.sh` | `platform_manager.sh start` |
| `daily_teardown.sh` | `platform_manager.sh stop` |
| `teardown_docker_stack.sh` | `platform_manager.sh stop` |
| `health_check.sh` | `platform_manager.sh health` |
| `verify_setup.sh` | `platform_manager.sh status` |

**Keep:**
- `validate_pipeline.py` - Called by platform_manager
- All `scripts/setup/*` - Needed for deployment

---

## Testing Checklist

### Fresh Deployment Test

- [ ] Create new RDS with name `cost_analytics_db`
- [ ] Configure SSM parameters at `/pepsico/*`
- [ ] Launch fresh EC2 instance
- [ ] Run setup scripts
- [ ] Execute SQL init files (00, 01, 02, 03)
- [ ] Verify users created: `etl_analytics`, `grafana_ro`
- [ ] Verify new tables exist: `tool_configurations`, `audit_etl_runs`
- [ ] Run `platform_manager.sh health` - all checks pass
- [ ] Run `platform_manager.sh start` - containers start
- [ ] Run ETL pipeline - data loads
- [ ] Verify `tool_configurations` shows active tools
- [ ] Verify `audit_etl_runs` has records with `tool_name`
- [ ] Connect Grafana with `grafana_ro` user
- [ ] Dashboards display data correctly

### Platform Manager Test

- [ ] `platform_manager.sh start` - starts successfully
- [ ] `platform_manager.sh status` - shows correct info
- [ ] `platform_manager.sh health` - all checks pass
- [ ] `platform_manager.sh logs` - displays container logs
- [ ] `platform_manager.sh validate` - runs Python validator
- [ ] `platform_manager.sh db` - connects to database
- [ ] `platform_manager.sh ssm` - lists parameters
- [ ] `platform_manager.sh stop` - stops cleanly
- [ ] `platform_manager.sh restart` - restarts successfully
- [ ] `platform_manager.sh clean` - cleans up resources

---

## Python Updates Needed

### In Each ETL Script

1. **Update audit logging to include tool_name:**

```python
# OLD
audit_logger.log_run(
    pipeline_stage='extract',
    status='success',
    records_processed=count
)

# NEW
audit_logger.log_run(
    tool_name='appdynamics',  # or 'servicenow'
    pipeline_stage='extract',
    status='success',
    records_processed=count
)
```

2. **Check tool is active before running:**

```python
# At start of ETL
tool_active = db.query(
    "SELECT is_active FROM tool_configurations WHERE tool_name = %s",
    ('appdynamics',)
)
if not tool_active or not tool_active[0][0]:
    logger.info("Tool appdynamics is not active, skipping")
    return
```

3. **Update last_successful_run:**

```python
# At end of successful ETL
db.execute(
    "UPDATE tool_configurations SET last_successful_run = NOW() WHERE tool_name = %s",
    ('appdynamics',)
)
```

---

## Rollback Plan

If issues occur:

1. **Keep old SSM parameters** - Don't delete `/aspectiq/demo/` until validated
2. **Git rollback**: `git checkout HEAD~1 -- sql/ docker-compose.ec2.yaml entrypoint.sh`
3. **Database restore**: Keep backup of old database
4. **Use old scripts**: They still exist in git history

---

## Benefits

✅ **Tool Agnostic** - No vendor-specific naming  
✅ **Extensible** - Add Elastic/Datadog/Splunk without breaking changes  
✅ **Professional** - Client-scoped SSM paths  
✅ **Maintainable** - Consolidated scripts  
✅ **Auditable** - Track runs per tool  
✅ **Configurable** - Enable/disable tools from database  
✅ **Future-Proof** - Framework ready for growth  

---

## Next Steps

1. **Test fresh deployment** with new naming
2. **Verify all ETL scripts work** with new database/user
3. **Update Python audit logging** to use `tool_name`
4. **Test platform_manager.sh** all commands
5. **Update documentation** with new naming
6. **Delete deprecated scripts** after validation
7. **Add Elastic integration** when ready (framework in place!)

---

**Status: Ready for testing on fresh EC2/RDS deployment** ✅