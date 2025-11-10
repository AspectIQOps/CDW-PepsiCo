# Audit & Governance Capabilities

## Overview

This document details the comprehensive audit capabilities implemented to meet SoW requirements and provide full data governance and traceability.

## SoW Audit Requirements (Section 2.5.3)

### ✅ Required Audit Tables - All Implemented

| SoW Requirement | Table | Status | Purpose |
|----------------|-------|--------|---------|
| Job history | `etl_execution_log` | ✅ Complete | Simple job-level tracking |
| Full audit trail | `data_lineage` | ✅ Complete | Source-to-target data flow |
| Matching history | `reconciliation_log` | ✅ Complete | AppD↔ServiceNow reconciliation |
| Administrative changes | `user_actions` | ✅ Complete | Admin action logging |

### ✅ Enhanced Audit Table (Beyond SoW)

| Table | Purpose | Enhancement |
|-------|---------|-------------|
| `audit_etl_runs` | Advanced ETL tracking | UUID-based, stage-level, JSONB metadata |

---

## 1. ETL Execution Logging (`etl_execution_log`)

### Purpose
Simple, job-level tracking of ETL runs for operational monitoring.

### Schema
```sql
CREATE TABLE etl_execution_log (
    run_id SERIAL PRIMARY KEY,
    job_name VARCHAR(100),
    started_at TIMESTAMP DEFAULT NOW(),
    finished_at TIMESTAMP,
    status VARCHAR(20),           -- 'running', 'success', 'failed'
    rows_ingested INTEGER,
    error_message TEXT
);
```

### What Gets Logged
- Each ETL script execution (appd_etl.py, snow_etl.py, etc.)
- Start and end timestamps
- Success/failure status
- Row count processed
- Error details on failure

### Usage
```sql
-- Recent ETL runs
SELECT job_name, started_at, finished_at, status, rows_ingested
FROM etl_execution_log
ORDER BY started_at DESC
LIMIT 20;

-- Failed jobs in last 7 days
SELECT job_name, started_at, error_message
FROM etl_execution_log
WHERE status = 'failed'
  AND started_at > NOW() - INTERVAL '7 days';
```

### ETL Integration
Every ETL script logs to this table:
```python
# Start
cursor.execute("""
    INSERT INTO etl_execution_log (job_name, started_at, status)
    VALUES ('appd_etl', NOW(), 'running')
    RETURNING run_id
""")
run_id = cursor.fetchone()[0]

# End
cursor.execute("""
    UPDATE etl_execution_log
    SET finished_at = NOW(), status = 'success', rows_ingested = %s
    WHERE run_id = %s
""", (row_count, run_id))
```

---

## 2. Advanced ETL Tracking (`audit_etl_runs`)

### Purpose
Detailed, stage-level tracking with UUID-based correlation and JSONB metadata.

### Schema
```sql
CREATE TABLE audit_etl_runs (
    run_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tool_name VARCHAR(50) NOT NULL,         -- 'appdynamics', 'servicenow'
    pipeline_stage VARCHAR(50) NOT NULL,    -- 'extract', 'transform', 'load'
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    status VARCHAR(20) NOT NULL,            -- 'running', 'success', 'failed', 'partial'
    records_processed INTEGER,
    records_inserted INTEGER,
    records_updated INTEGER,
    records_failed INTEGER,
    error_message TEXT,
    metadata JSONB                          -- Tool-specific details
);
```

### What Gets Logged
- Per-stage execution (extract, transform, load)
- Detailed record counts (inserted vs updated vs failed)
- Tool-specific metadata in JSONB
- UUID for correlation across systems

### Usage
```sql
-- Stage-level performance
SELECT tool_name, pipeline_stage,
       AVG(EXTRACT(EPOCH FROM (end_time - start_time))) as avg_duration_seconds
FROM audit_etl_runs
WHERE status = 'success'
GROUP BY tool_name, pipeline_stage;

-- Failed records by tool
SELECT tool_name, SUM(records_failed) as total_failures
FROM audit_etl_runs
WHERE records_failed > 0
GROUP BY tool_name;
```

### JSONB Metadata Examples
```json
{
  "api_endpoint": "https://pepsi.saas.appdynamics.com",
  "applications_fetched": 156,
  "license_types": ["APM", "RUM"],
  "oauth_token_refreshed": true,
  "rate_limit_hit": false
}
```

---

## 3. Data Lineage Tracking (`data_lineage`)

### Purpose
Complete audit trail tracking every record from source system to database.

### Schema
```sql
CREATE TABLE data_lineage (
    lineage_id SERIAL PRIMARY KEY,
    source_system VARCHAR(50) NOT NULL,     -- 'appdynamics', 'servicenow', 'manual'
    source_table VARCHAR(100),              -- Source table/endpoint
    source_record_id VARCHAR(255),          -- Original record ID
    target_table VARCHAR(100) NOT NULL,     -- Database table
    target_record_id INTEGER,               -- DB record ID
    operation VARCHAR(20) NOT NULL,         -- 'insert', 'update', 'delete', 'merge'
    run_id UUID REFERENCES audit_etl_runs(run_id),
    execution_id INTEGER REFERENCES etl_execution_log(run_id),
    field_changes JSONB,                    -- Before/after values
    transform_applied VARCHAR(255),         -- Transformation description
    processed_at TIMESTAMP DEFAULT NOW()
);
```

### What Gets Logged
- Every insert/update/delete operation
- Source system and original ID
- Transformations applied
- Before/after field values for updates
- Correlation to ETL run

### Usage Examples

**Trace Application Record:**
```sql
-- Find all data sources for an application
SELECT source_system, source_table, source_record_id,
       operation, transform_applied, processed_at
FROM data_lineage
WHERE target_table = 'applications_dim'
  AND target_record_id = 123
ORDER BY processed_at;
```

**Impact Analysis:**
```sql
-- What would be affected if we delete AppD app ID 'APP-456'?
SELECT DISTINCT target_table, COUNT(*) as record_count
FROM data_lineage
WHERE source_system = 'appdynamics'
  AND source_record_id = 'APP-456'
GROUP BY target_table;
```

**Field Change Audit:**
```sql
-- See what changed for an application
SELECT processed_at, field_changes->>'before' as before_value,
       field_changes->>'after' as after_value
FROM data_lineage
WHERE target_table = 'applications_dim'
  AND target_record_id = 123
  AND operation = 'update'
ORDER BY processed_at DESC;
```

### ETL Integration Example
```python
def log_lineage(cursor, source_sys, source_id, target_table, target_id, operation, run_id):
    cursor.execute("""
        INSERT INTO data_lineage
        (source_system, source_record_id, target_table, target_record_id,
         operation, run_id, processed_at)
        VALUES (%s, %s, %s, %s, %s, %s, NOW())
    """, (source_sys, source_id, target_table, target_id, operation, run_id))

# Usage in appd_etl.py
cursor.execute("INSERT INTO applications_dim (...) VALUES (...) RETURNING app_id")
app_id = cursor.fetchone()[0]
log_lineage(cursor, 'appdynamics', appd_app_id, 'applications_dim', app_id, 'insert', run_id)
```

---

## 4. Reconciliation Logging (`reconciliation_log`)

### Purpose
Track fuzzy matching and reconciliation between AppDynamics and ServiceNow.

### Schema
```sql
CREATE TABLE reconciliation_log (
    log_id SERIAL PRIMARY KEY,
    source_a VARCHAR(50),            -- 'AppDynamics'
    source_b VARCHAR(50),            -- 'ServiceNow'
    match_key_a VARCHAR(255),        -- AppD app name
    match_key_b VARCHAR(255),        -- ServiceNow service name
    confidence_score DECIMAL(5,2),   -- 0-100 similarity score
    match_status VARCHAR(50),        -- 'auto_matched', 'needs_review', 'rejected'
    resolved_app_id INTEGER REFERENCES applications_dim(app_id),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### What Gets Logged
- Every reconciliation attempt
- Confidence scores for fuzzy matches
- Auto-matched vs manual review items
- Final resolution (which app_id was used)

### Usage Examples

**Match Quality Report:**
```sql
SELECT match_status,
       COUNT(*) as count,
       AVG(confidence_score) as avg_confidence
FROM reconciliation_log
GROUP BY match_status;
```

**Needs Review Queue:**
```sql
-- Applications needing manual review (50-80% confidence)
SELECT match_key_a as appd_name,
       match_key_b as snow_name,
       confidence_score
FROM reconciliation_log
WHERE match_status = 'needs_review'
ORDER BY confidence_score DESC;
```

**Reconciliation History:**
```sql
-- How was this application matched?
SELECT source_a, match_key_a, source_b, match_key_b,
       confidence_score, match_status, created_at
FROM reconciliation_log
WHERE resolved_app_id = 123;
```

---

## 5. User Action Auditing (`user_actions`)

### Purpose
Log all administrative changes made through dashboard or manual scripts.

### Schema
```sql
CREATE TABLE user_actions (
    action_id SERIAL PRIMARY KEY,
    user_name VARCHAR(100) NOT NULL,
    user_email VARCHAR(255),
    action_type VARCHAR(50) NOT NULL,    -- 'price_update', 'mapping_override', etc.
    target_table VARCHAR(100),
    target_record_id INTEGER,
    action_details JSONB NOT NULL,       -- What changed
    reason TEXT,                         -- Why was it changed
    ip_address VARCHAR(50),
    performed_at TIMESTAMP DEFAULT NOW()
);
```

### What Gets Logged
- Price configuration changes
- Manual H-code overrides
- Sector/owner reassignments
- Configuration updates
- Manual data corrections

### Usage Examples

**Admin Activity Report:**
```sql
-- Recent admin changes
SELECT user_name, action_type, target_table,
       reason, performed_at
FROM user_actions
ORDER BY performed_at DESC
LIMIT 50;
```

**Price Change Audit:**
```sql
-- Who changed pricing?
SELECT user_name, user_email,
       action_details->>'capability' as capability,
       action_details->>'tier' as tier,
       action_details->>'old_rate' as old_rate,
       action_details->>'new_rate' as new_rate,
       reason, performed_at
FROM user_actions
WHERE action_type = 'price_update'
ORDER BY performed_at DESC;
```

**H-Code Override Tracking:**
```sql
-- All H-code manual overrides
SELECT user_name,
       action_details->>'app_name' as application,
       action_details->>'h_code' as h_code_assigned,
       reason, performed_at
FROM user_actions
WHERE action_type = 'mapping_override'
  AND action_details->>'field' = 'h_code';
```

### Integration Example
```python
def log_user_action(cursor, user, email, action_type, details, reason, ip):
    cursor.execute("""
        INSERT INTO user_actions
        (user_name, user_email, action_type, action_details, reason, ip_address)
        VALUES (%s, %s, %s, %s, %s, %s)
    """, (user, email, action_type, json.dumps(details), reason, ip))

# Usage when admin updates price
details = {
    'capability': 'APM',
    'tier': 'Peak',
    'old_rate': 0.75,
    'new_rate': 0.80,
    'effective_date': '2025-01-01'
}
log_user_action(cursor, 'john.doe', 'john@pepsico.com', 'price_update',
                details, 'Contract renewal rate increase', '10.0.1.45')
```

---

## Comprehensive Audit Queries

### 1. End-to-End Data Lineage
```sql
-- Trace a usage record from AppD API to chargeback
WITH source_data AS (
    SELECT * FROM data_lineage
    WHERE target_table = 'license_usage_fact'
      AND target_record_id = 12345
),
cost_calc AS (
    SELECT * FROM data_lineage
    WHERE target_table = 'license_cost_fact'
      AND source_record_id = '12345'
),
chargeback_data AS (
    SELECT * FROM data_lineage
    WHERE target_table = 'chargeback_fact'
      AND source_table = 'license_cost_fact'
)
SELECT 'usage' as stage, * FROM source_data
UNION ALL
SELECT 'cost', * FROM cost_calc
UNION ALL
SELECT 'chargeback', * FROM chargeback_data;
```

### 2. ETL Performance Dashboard
```sql
SELECT
    el.job_name,
    COUNT(*) as runs,
    AVG(EXTRACT(EPOCH FROM (el.finished_at - el.started_at))) as avg_duration_sec,
    SUM(el.rows_ingested) as total_rows,
    SUM(CASE WHEN el.status = 'failed' THEN 1 ELSE 0 END) as failures
FROM etl_execution_log el
WHERE el.started_at > NOW() - INTERVAL '30 days'
GROUP BY el.job_name;
```

### 3. Data Quality Audit
```sql
-- Find applications with incomplete data
SELECT
    ad.app_id,
    ad.appd_application_name,
    ad.sn_service_name,
    CASE WHEN ad.h_code IS NULL THEN 'Missing H-Code' END as h_code_status,
    CASE WHEN ad.owner_id = 1 THEN 'Unassigned Owner' END as owner_status,
    CASE WHEN ad.sector_id = 1 THEN 'Unassigned Sector' END as sector_status,
    (SELECT COUNT(*) FROM reconciliation_log WHERE resolved_app_id = ad.app_id) as recon_attempts
FROM applications_dim ad
WHERE ad.h_code IS NULL
   OR ad.owner_id = 1
   OR ad.sector_id = 1;
```

### 4. Compliance Report
```sql
-- 30-day audit report for compliance
SELECT
    'ETL Runs' as audit_area,
    COUNT(*) as record_count,
    MIN(started_at) as earliest_record,
    MAX(started_at) as latest_record
FROM etl_execution_log
WHERE started_at > NOW() - INTERVAL '30 days'

UNION ALL

SELECT
    'Data Lineage',
    COUNT(*),
    MIN(processed_at),
    MAX(processed_at)
FROM data_lineage
WHERE processed_at > NOW() - INTERVAL '30 days'

UNION ALL

SELECT
    'User Actions',
    COUNT(*),
    MIN(performed_at),
    MAX(performed_at)
FROM user_actions
WHERE performed_at > NOW() - INTERVAL '30 days'

UNION ALL

SELECT
    'Reconciliations',
    COUNT(*),
    MIN(created_at),
    MAX(created_at)
FROM reconciliation_log
WHERE created_at > NOW() - INTERVAL '30 days';
```

---

## Dashboard Requirements

### Tab 8: Admin Panel (SoW Section 2.6.1)

Should include audit visualization panels:

1. **ETL Health Monitor**
   - Recent runs with status
   - Average duration trends
   - Failure rate by job
   - Source: `etl_execution_log`, `audit_etl_runs`

2. **Data Quality Dashboard**
   - Records missing H-codes
   - Unassigned owners/sectors
   - Reconciliation pending review
   - Source: `data_lineage`, `reconciliation_log`

3. **Audit Logs**
   - Recent admin actions
   - Price change history
   - Manual override log
   - Source: `user_actions`

4. **Data Lineage Viewer**
   - Search by application
   - Trace record origins
   - Show transformation chain
   - Source: `data_lineage`

---

## Retention & Archival

### Retention Policies (Recommended)

| Table | Retention | Archival Strategy |
|-------|-----------|-------------------|
| `etl_execution_log` | 1 year online | Archive to S3 quarterly |
| `audit_etl_runs` | 1 year online | Archive to S3 quarterly |
| `data_lineage` | 2 years online | Archive to S3 annually |
| `reconciliation_log` | Indefinite | No archival (reference data) |
| `user_actions` | 7 years | Required for compliance |

### Archival Script
```sql
-- Example: Archive old ETL logs
INSERT INTO etl_execution_log_archive
SELECT * FROM etl_execution_log
WHERE started_at < NOW() - INTERVAL '1 year';

DELETE FROM etl_execution_log
WHERE started_at < NOW() - INTERVAL '1 year';
```

---

## SoW Compliance Summary

### ✅ All Audit Requirements Met

| SoW Requirement | Implementation | Status |
|----------------|----------------|--------|
| Job execution history | `etl_execution_log` | ✅ Complete |
| Full audit trail | `data_lineage` | ✅ Complete |
| Reconciliation tracking | `reconciliation_log` | ✅ Complete |
| Administrative changes | `user_actions` | ✅ Complete |
| Per-stage metrics | `audit_etl_runs` | ✅ Enhanced |

### ✅ Additional Governance Features

- UUID-based run correlation
- JSONB metadata for flexibility
- Field-level change tracking
- IP address logging for security
- Reason codes for all changes
- Confidence scoring for matches
- Before/after value storage

---

## Testing Checklist

- [ ] ETL scripts log to `etl_execution_log`
- [ ] Data lineage captured on all inserts/updates
- [ ] Reconciliation logs fuzzy match results
- [ ] User actions logged from admin UI
- [ ] Dashboard displays audit data
- [ ] Retention policies configured
- [ ] Archive process tested
- [ ] Compliance reports generated
- [ ] Data lineage trace works end-to-end
- [ ] Audit logs are immutable (no updates/deletes)

---

## References

- SoW Section 2.5.3: Audit Tables
- SoW Section 2.7: Configurability & Maintenance
- [00_complete_init.sql](../sql/init/00_complete_init.sql) - Schema definition
- [database_schema_sow_compliance.md](database_schema_sow_compliance.md) - Full schema documentation
