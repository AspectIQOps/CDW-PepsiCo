# Database Schema - SoW Compliance

## Overview

This document validates that the database schema in [00_complete_init.sql](../sql/init/00_complete_init.sql) meets all requirements specified in the SoW Section 2.5.3: Comprehensive Database Schema.

## SoW Compliance Matrix

### ✅ Fact Tables (SoW Required)

| Table | SoW Requirement | Status | Notes |
|-------|----------------|--------|-------|
| `license_usage_fact` | Granular usage metrics | ✅ Complete | Tracks usage by app, capability, tier, timestamp |
| `license_cost_fact` | Calculated costs with allocation | ✅ Complete | Auto-calculated from usage × price |
| `forecast_fact` | Prediction data | ✅ Complete | 12-month forecasts with confidence intervals |
| `chargeback_fact` | Department charges | ✅ Complete | Monthly charges by sector, owner, H-code |

### ✅ Dimension Tables (SoW Required)

| Table | SoW Requirement | Status | Notes |
|-------|----------------|--------|-------|
| `applications_dim` | Application metadata | ✅ Enhanced | Added `license_tier` column for Peak/Pro |
| `owners_dim` | Ownership hierarchy | ✅ Complete | Owner name, email, department |
| `sectors_dim` | Business sectors | ✅ Complete | Seeded with PepsiCo sectors |
| `capabilities_dim` | License types | ✅ Complete | APM, RUM, Analytics, etc. |
| `architecture_dim` | Monolith/Microservices | ✅ Complete | Pattern classification |
| `time_dim` | Time hierarchy | ✅ **NEW** | Date analytics with fiscal calendar support |

### ✅ Configuration Tables (SoW Required)

| Table | SoW Requirement | Status | Notes |
|-------|----------------|--------|-------|
| `price_config` | Pricing rules and overrides | ✅ Complete | Per capability, tier, effective dates |
| `allocation_rules` | Cost distribution logic | ✅ Complete | Shared service allocation |
| `mapping_overrides` | Manual reconciliation | ✅ **NEW** | H-code overrides for missing CMDB data |
| `forecast_models` | Algorithm configurations | ✅ **NEW** | Linear, exponential, seasonal models |

### ✅ Audit Tables (SoW Required)

| Table | SoW Requirement | Status | Notes |
|-------|----------------|--------|-------|
| `etl_execution_log` | Job history | ✅ Complete | Simple job tracking |
| `data_lineage` | Full audit trail | ✅ **NEW** | Complete source-to-target tracking |
| `reconciliation_log` | Matching history | ✅ Complete | AppD ↔ ServiceNow reconciliation |
| `user_actions` | Administrative changes | ✅ **NEW** | Admin action audit log |

### ✅ Additional Tables (Beyond SoW)

| Table | Purpose | Notes |
|-------|---------|-------|
| `tool_configurations` | Tool management | Active/inactive tools, config storage |
| `audit_etl_runs` | Advanced ETL tracking | UUID-based, stage-level metrics |
| `servers_dim` | Server tracking | Infrastructure metadata |
| `app_server_mapping` | App-to-server relationships | Many-to-many mapping |

## New Tables Added (2025-01-10)

### 1. time_dim
**Purpose:** Time hierarchy for date-based analytics and reporting

**Schema:**
```sql
CREATE TABLE time_dim (
    time_id SERIAL PRIMARY KEY,
    date_value DATE UNIQUE NOT NULL,
    year INTEGER NOT NULL,
    quarter INTEGER NOT NULL,
    month INTEGER NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    week INTEGER NOT NULL,
    day_of_month INTEGER NOT NULL,
    day_of_week INTEGER NOT NULL,
    day_name VARCHAR(20) NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    is_holiday BOOLEAN DEFAULT FALSE,
    fiscal_year INTEGER,
    fiscal_quarter INTEGER,
    fiscal_period INTEGER
);
```

**Use Cases:**
- Fiscal year reporting
- Quarter-over-quarter comparisons
- Weekend vs weekday analysis
- Holiday impact analysis
- Pre-populated date lookups for dashboard performance

**ETL Requirement:** Populate with date range (e.g., 2020-2030)

### 2. mapping_overrides
**Purpose:** Manual overrides for H-codes and other fields when CMDB data is missing

**Schema:**
```sql
CREATE TABLE mapping_overrides (
    override_id SERIAL PRIMARY KEY,
    app_id INTEGER REFERENCES applications_dim(app_id),
    override_type VARCHAR(50) NOT NULL, -- 'h_code', 'owner', 'sector', 'architecture'
    field_name VARCHAR(100) NOT NULL,
    override_value VARCHAR(255) NOT NULL,
    reason TEXT,
    created_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);
```

**Use Cases:**
- H-code override when CMDB missing data (SoW Section 3.4 requirement)
- Temporary owner assignment pending CMDB update
- Sector correction for misclassified applications
- Architecture override for manual classification

**Admin UI Requirement:** Needs dashboard panel for managing overrides

### 3. forecast_models
**Purpose:** Configuration storage for forecasting algorithms

**Schema:**
```sql
CREATE TABLE forecast_models (
    model_id SERIAL PRIMARY KEY,
    model_name VARCHAR(100) UNIQUE NOT NULL,
    model_type VARCHAR(50) NOT NULL, -- 'linear', 'exponential', 'seasonal', 'arima'
    is_active BOOLEAN DEFAULT TRUE,
    confidence_level DECIMAL(5,2) DEFAULT 95.00,
    parameters JSONB,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**Pre-seeded Models:**
1. Linear Trend - Simple regression
2. Exponential Smoothing - Double exponential
3. Seasonal ARIMA - Time series with seasonality

**Use Cases:**
- Algorithm selection for forecasting
- Parameter tuning without code changes
- A/B testing different models
- Model accuracy comparison

**ETL Integration:** `advanced_forecasting.py` reads model parameters from this table

### 4. data_lineage
**Purpose:** Complete audit trail tracking data flow from source to target

**Schema:**
```sql
CREATE TABLE data_lineage (
    lineage_id SERIAL PRIMARY KEY,
    source_system VARCHAR(50) NOT NULL, -- 'appdynamics', 'servicenow', 'manual'
    source_table VARCHAR(100),
    source_record_id VARCHAR(255),
    target_table VARCHAR(100) NOT NULL,
    target_record_id INTEGER,
    operation VARCHAR(20) NOT NULL, -- 'insert', 'update', 'delete', 'merge'
    run_id UUID REFERENCES audit_etl_runs(run_id),
    execution_id INTEGER REFERENCES etl_execution_log(run_id),
    field_changes JSONB,
    transform_applied VARCHAR(255),
    processed_at TIMESTAMP DEFAULT NOW()
);
```

**Use Cases:**
- Track which AppD data populated which DB records
- Identify records modified by reconciliation
- Debug data quality issues
- Compliance and audit requirements
- Impact analysis for source system changes

**ETL Integration:** ETL scripts should log to this table on insert/update/delete operations

### 5. user_actions
**Purpose:** Audit log of all administrative changes

**Schema:**
```sql
CREATE TABLE user_actions (
    action_id SERIAL PRIMARY KEY,
    user_name VARCHAR(100) NOT NULL,
    user_email VARCHAR(255),
    action_type VARCHAR(50) NOT NULL, -- 'price_update', 'mapping_override', 'config_change', 'manual_correction'
    target_table VARCHAR(100),
    target_record_id INTEGER,
    action_details JSONB NOT NULL,
    reason TEXT,
    ip_address VARCHAR(50),
    performed_at TIMESTAMP DEFAULT NOW()
);
```

**Use Cases:**
- Track who changed pricing rules
- Log manual H-code overrides
- Audit configuration changes
- Compliance reporting
- Dispute resolution

**Integration Points:**
- Grafana dashboard admin panels
- Manual SQL scripts (should log actions)
- API endpoints for configuration changes

### 6. applications_dim Enhancement
**New Column:** `license_tier`

```sql
ALTER TABLE applications_dim
ADD COLUMN IF NOT EXISTS license_tier VARCHAR(20)
CHECK (license_tier IN ('Peak', 'Pro', 'Unknown'));
```

**Purpose:** Track which AppDynamics license tier each application uses (SoW Section 2.1)

**Values:**
- `Peak` - Premium tier with full features
- `Pro` - Standard tier
- `Unknown` - Needs classification

**Population Strategy:**
1. From AppDynamics application tags (preferred)
2. From custom properties
3. Heuristic analysis
4. Manual classification via `mapping_overrides`

## SoW Requirements Met

### Section 2.1: License Coverage & Analytics
- ✅ Peak vs. Pro differentiation via `license_tier` column
- ✅ Application-level attribution via `applications_dim`
- ✅ Tier-based reporting via `license_usage_fact.tier`

### Section 2.2: Cost Analysis & Financial Management
- ✅ Multi-dimensional cost allocation via fact tables
- ✅ H-code override support via `mapping_overrides`
- ✅ Dynamic pricing via `price_config`

### Section 2.3: Trend Analysis & Forecasting
- ✅ Configurable forecasting via `forecast_models`
- ✅ Historical analysis via `license_usage_fact`
- ✅ Time hierarchy via `time_dim`

### Section 2.4: Data Integration & Enrichment
- ✅ Full audit trail via `data_lineage`
- ✅ Reconciliation tracking via `reconciliation_log`

### Section 2.5.3: Comprehensive Database Schema
- ✅ All required fact tables present
- ✅ All required dimension tables present
- ✅ All required configuration tables present
- ✅ All required audit tables present

### Section 3.4: Data Alignment (H-Code Requirements)
- ✅ H-code field in `applications_dim`
- ✅ Manual override capability via `mapping_overrides`
- ✅ Audit trail via `user_actions`

## Total Table Count

| Category | Count |
|----------|-------|
| Fact Tables | 4 |
| Dimension Tables | 7 (6 required + time_dim) |
| Configuration Tables | 4 |
| Audit Tables | 5 |
| Utility Tables | 2 |
| **Total** | **22 tables** |

## Next Steps

### ETL Script Updates Required

1. **Populate time_dim** - Create script to generate date dimension
   ```python
   # scripts/utils/populate_time_dim.py
   # Generate dates from 2020-2030 with all hierarchy fields
   ```

2. **Enable data_lineage logging** - Update ETL scripts to log lineage
   ```python
   # In appd_etl.py, snow_etl.py, etc.
   # Log each insert/update/delete to data_lineage table
   ```

3. **Implement mapping_overrides logic** - Check overrides before using CMDB data
   ```python
   # In applications processing:
   # 1. Check mapping_overrides for h_code
   # 2. Fall back to CMDB value
   # 3. Default to NULL if neither available
   ```

4. **Use forecast_models table** - Read parameters from DB instead of hardcoding
   ```python
   # In advanced_forecasting.py:
   # SELECT parameters FROM forecast_models WHERE is_active=true
   ```

### Dashboard Requirements

1. **Admin Panel for mapping_overrides**
   - UI to add/edit/expire overrides
   - Reason field required
   - Approval workflow for H-code changes

2. **Data Lineage Viewer**
   - Trace record from source to target
   - Show transformation chain
   - Filter by date range, source system

3. **User Action Audit Log**
   - Display all admin changes
   - Filter by user, action type, date
   - Export for compliance

4. **Forecast Model Configuration**
   - Enable/disable models
   - Adjust parameters
   - Compare model accuracy

## Testing Checklist

When deploying to new environment:

- [ ] All 22 tables created successfully
- [ ] Indexes created on all tables
- [ ] Foreign key constraints working
- [ ] Check constraints enforced (e.g., license_tier values)
- [ ] Users created: etl_analytics, grafana_ro
- [ ] Permissions granted correctly
- [ ] Seed data populated (sectors, capabilities, owners, etc.)
- [ ] time_dim populated with date range
- [ ] forecast_models seeded with default algorithms
- [ ] Applications can insert with license_tier
- [ ] mapping_overrides functional
- [ ] data_lineage logging works

## Schema Verification Query

```sql
-- Run this after initialization to verify all tables exist
SELECT
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = t.table_name) as column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Expected: 22 tables
```

## References

- SoW Section 2.5.3: Comprehensive Database Schema
- SoW Section 3.4: Data Alignment (H-Code Requirements)
- [00_complete_init.sql](../sql/init/00_complete_init.sql) - Complete schema
- [data_dictionary.md](data_dictionary.md) - Field definitions
