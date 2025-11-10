# PepsiCo AppDynamics License Management
## Data Dictionary v1.0

**Last Updated:** October 30, 2025  
**Database:** PostgreSQL 16  
**Schema:** public  
**Purpose:** Comprehensive data model for AppDynamics license tracking, cost allocation, and chargeback across PepsiCo business units

---

## Table of Contents

1. [Dimension Tables](#dimension-tables)
2. [Fact Tables](#fact-tables)
3. [Configuration Tables](#configuration-tables)
4. [Audit Tables](#audit-tables)
5. [Views](#views)
6. [Calculation Methodologies](#calculation-methodologies)
7. [Data Lineage](#data-lineage)

---

## Dimension Tables

### applications_dim
**Purpose:** Master application registry linking AppDynamics monitoring data with ServiceNow CMDB records

**Primary Key:** `app_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `app_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `appd_application_id` | INT | NULL | AppDynamics application identifier | AppDynamics REST API | 12345 |
| `appd_application_name` | TEXT | NULL | Application name in AppDynamics | AppDynamics REST API | "Supply Chain Visibility" |
| `sn_sys_id` | TEXT | NULL | ServiceNow sys_id (CMDB unique ID) | ServiceNow cmdb_ci_service | "a1b2c3d4e5f6..." |
| `sn_service_name` | TEXT | NULL | Service name in ServiceNow CMDB | ServiceNow cmdb_ci_service | "Supply Chain App (Prod)" |
| `owner_id` | INT | NOT NULL | Foreign key to owners_dim | ServiceNow owned_by/managed_by | 3 |
| `sector_id` | INT | NOT NULL | Foreign key to sectors_dim | ServiceNow u_sector/business_unit | 2 |
| `architecture_id` | INT | NOT NULL | Foreign key to architecture_dim | ServiceNow u_architecture_type | 2 |
| `h_code` | TEXT | NULL | Cost center / H-code for chargeback | ServiceNow u_h_code/cost_center | "BEV-001" |
| `is_critical` | BOOLEAN | NULL | Business criticality flag | ServiceNow operational_status | true |
| `support_group` | TEXT | NULL | Support team assignment | ServiceNow support_group | "Platform Engineering" |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |
| `updated_at` | TIMESTAMP | NOT NULL | Last update timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `app_id`
- Unique: `appd_application_id`, `sn_sys_id`
- Standard: `owner_id`, `sector_id`, `h_code`

**Business Rules:**
- At least one of `appd_application_id` or `sn_sys_id` must be populated
- `owner_id`, `sector_id`, `architecture_id` default to 1 ("Unassigned") if not known
- H-code population is PepsiCo's responsibility via ServiceNow
- Reconciliation engine links AppDynamics and ServiceNow records via fuzzy matching

---

### owners_dim
**Purpose:** Application ownership hierarchy for chargeback attribution

**Primary Key:** `owner_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `owner_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `owner_name` | TEXT | NOT NULL | Owner/team name | ServiceNow owned_by | "Platform Engineering Team" |
| `organizational_hierarchy` | TEXT | NULL | Organizational path | ServiceNow | "IT > Infrastructure > Platform" |
| `email` | TEXT | NULL | Contact email | ServiceNow | "platform-eng@pepsico.com" |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |
| `updated_at` | TIMESTAMP | NOT NULL | Last update timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `owner_id`
- Unique: `owner_name`

**Business Rules:**
- Default owner "Unassigned" (owner_id = 1) created during seed data load

---

### sectors_dim
**Purpose:** Business sectors/divisions for cost allocation (e.g., Beverages, Frito-Lay, Quaker)

**Primary Key:** `sector_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `sector_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `sector_name` | TEXT | NOT NULL | Business sector name | ServiceNow u_sector | "Beverages North America" |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |

**Indexes:**
- Primary Key: `sector_id`
- Unique: `sector_name`

**Business Rules:**
- Default sector "Unassigned" (sector_id = 1) created during seed data load

---

### architecture_dim
**Purpose:** Application architecture patterns (Monolith, Microservices, Hybrid)

**Primary Key:** `architecture_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `architecture_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `pattern_name` | TEXT | NOT NULL | Architecture pattern | ServiceNow u_architecture_type | "Microservices" |
| `description` | TEXT | NULL | Pattern description | Manual | "Container-based microservices" |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |

**Indexes:**
- Primary Key: `architecture_id`
- Unique: `pattern_name`

**Business Rules:**
- Used for license efficiency analysis (Monolith vs. Microservices)
- Default "Unknown" (architecture_id = 1) created during seed data load

---

### capabilities_dim
**Purpose:** License capability types (APM, RUM, Synthetic, Database Monitoring)

**Primary Key:** `capability_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `capability_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `capability_code` | TEXT | NOT NULL | License capability code | AppDynamics license types | "APM" |
| `description` | TEXT | NULL | Capability description | Manual | "Application Performance Monitoring" |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |

**Indexes:**
- Primary Key: `capability_id`
- Unique: `capability_code`

**Seeded Values:**
- APM: Application Performance Monitoring
- MRUM: Mobile Real User Monitoring
- BRUM: Browser Real User Monitoring
- Synthetic: Synthetic Monitoring
- DB: Database Monitoring

---

### time_dim
**Purpose:** Time dimension for temporal analysis and reporting

**Primary Key:** `time_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `time_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `ts` | TIMESTAMP | NOT NULL | Timestamp | Pre-populated | 2025-01-01 00:00:00 |
| `year` | INT | NOT NULL | Year | Derived from ts | 2025 |
| `month` | INT | NOT NULL | Month (1-12) | Derived from ts | 1 |
| `day` | INT | NOT NULL | Day (1-31) | Derived from ts | 1 |
| `day_name` | TEXT | NULL | Day of week | Derived from ts | "Monday" |
| `month_name` | TEXT | NULL | Month name | Derived from ts | "January" |
| `quarter` | TEXT | NULL | Quarter | Derived from ts | "Q1" |
| `yyyy_mm` | TEXT | NOT NULL | Year-Month string | Derived from ts | "2025-01" |

**Indexes:**
- Primary Key: `time_id`
- Unique: `ts`
- Standard: `yyyy_mm`

**Business Rules:**
- Pre-populated with hourly/daily timestamps for reporting periods

---

### servers_dim
**Purpose:** Server configuration items from ServiceNow CMDB

**Primary Key:** `server_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `server_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `sn_sys_id` | TEXT | NOT NULL | ServiceNow sys_id | ServiceNow cmdb_ci_server | "z9y8x7w6v5u4..." |
| `server_name` | TEXT | NULL | Server hostname | ServiceNow cmdb_ci_server.name | "app-prod-01.pepsico.com" |
| `ip_address` | TEXT | NULL | IP address | ServiceNow cmdb_ci_server.ip_address | "10.1.2.3" |
| `os` | TEXT | NULL | Operating system | ServiceNow cmdb_ci_server.os | "Red Hat Enterprise Linux 8" |
| `is_virtual` | BOOLEAN | NULL | Virtual machine flag | ServiceNow cmdb_ci_server.virtual | true |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |
| `updated_at` | TIMESTAMP | NOT NULL | Last update timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `server_id`
- Unique: `sn_sys_id`

---

### app_server_mapping
**Purpose:** Application-to-server relationships from ServiceNow CMDB

**Primary Key:** `mapping_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `mapping_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `app_id` | INT | NOT NULL | Foreign key to applications_dim | ServiceNow cmdb_rel_ci (parent) | 5 |
| `server_id` | INT | NOT NULL | Foreign key to servers_dim | ServiceNow cmdb_rel_ci (child) | 12 |
| `relationship_type` | TEXT | NULL | Relationship type | ServiceNow cmdb_rel_ci.type | "Runs on" |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |

**Indexes:**
- Primary Key: `mapping_id`
- Unique: `(app_id, server_id)`
- Standard: `app_id`, `server_id`

**Business Rules:**
- Extracted from ServiceNow cmdb_rel_ci table (type = "Runs on::Runs")
- Used for infrastructure cost allocation (future enhancement)

---

## Fact Tables

### license_usage_fact
**Purpose:** Granular daily license usage metrics from AppDynamics

**Primary Key:** `usage_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `usage_id` | BIGSERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `ts` | TIMESTAMP | NOT NULL | Usage timestamp (daily granularity) | AppDynamics API | 2025-10-15 00:00:00 |
| `app_id` | INT | NOT NULL | Foreign key to applications_dim | Linked via reconciliation | 5 |
| `capability_id` | INT | NOT NULL | Foreign key to capabilities_dim | AppDynamics license type | 1 (APM) |
| `tier` | TEXT | NOT NULL | License tier | AppDynamics metadata | "PEAK" or "PRO" |
| `units_consumed` | NUMERIC | NOT NULL | License units consumed | AppDynamics usage metrics | 123.45 |
| `nodes_count` | INT | NULL | Number of monitored nodes | AppDynamics node count | 12 |
| `servers_count` | INT | NULL | Number of servers (future) | ServiceNow relationships | 8 |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `usage_id`
- Standard: `ts`, `app_id`, `capability_id`
- Composite: `(ts, app_id, capability_id, tier)` for query performance

**Business Rules:**
- `tier` must be 'PEAK' or 'PRO'
- `units_consumed` represents daily license consumption
- Used as input for cost calculation via `price_config` table

**Calculation Sources:**
```sql
-- Example: Daily APM usage for an application
SELECT 
    ts::date,
    SUM(units_consumed) as total_daily_units
FROM license_usage_fact
WHERE app_id = 5 
  AND capability_id = 1
GROUP BY ts::date;
```

---

### license_cost_fact
**Purpose:** Calculated license costs with pricing attribution

**Primary Key:** `cost_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `cost_id` | BIGSERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `ts` | TIMESTAMP | NOT NULL | Cost date (matches usage date) | From license_usage_fact | 2025-10-15 00:00:00 |
| `app_id` | INT | NOT NULL | Foreign key to applications_dim | From license_usage_fact | 5 |
| `capability_id` | INT | NOT NULL | Foreign key to capabilities_dim | From license_usage_fact | 1 (APM) |
| `tier` | TEXT | NOT NULL | License tier | From license_usage_fact | "PEAK" |
| `usd_cost` | NUMERIC(12,2) | NOT NULL | Daily cost in USD | **CALCULATED** (see below) | 456.78 |
| `price_id` | INT | NULL | Foreign key to price_config | Pricing rule applied | 3 |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `cost_id`
- Standard: `ts`, `app_id`
- Composite: `(ts, app_id, capability_id)` for aggregation queries

**Business Rules:**
- Automatically calculated during ETL from `license_usage_fact` + `price_config`
- Cost calculation formula: `usd_cost = units_consumed × unit_rate`
- Pricing rules applied based on effective date range

**Calculation Methodology:**
```sql
-- Cost calculation query (performed in appd_etl.py)
INSERT INTO license_cost_fact (ts, app_id, capability_id, tier, usd_cost, price_id)
SELECT 
    u.ts,
    u.app_id,
    u.capability_id,
    u.tier,
    ROUND((u.units_consumed * p.unit_rate)::numeric, 2) AS usd_cost,
    p.price_id
FROM license_usage_fact u
JOIN price_config p 
    ON u.capability_id = p.capability_id
    AND u.tier = p.tier
    AND u.ts::date BETWEEN p.start_date AND COALESCE(p.end_date, u.ts::date);
```

---

### forecast_fact
**Purpose:** 12-24 month license usage projections with confidence intervals

**Primary Key:** `forecast_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `forecast_id` | BIGSERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `month_start` | DATE | NOT NULL | Forecast month start date | Calculated (first of month) | 2025-11-01 |
| `app_id` | INT | NOT NULL | Foreign key to applications_dim | From historical usage | 5 |
| `capability_id` | INT | NOT NULL | Foreign key to capabilities_dim | From historical usage | 1 (APM) |
| `tier` | TEXT | NOT NULL | License tier | From historical usage | "PEAK" |
| `projected_units` | NUMERIC | NULL | Forecasted monthly units | **ML MODEL OUTPUT** | 3456.78 |
| `projected_cost` | NUMERIC(12,2) | NULL | Forecasted monthly cost | projected_units × unit_rate | 12345.67 |
| `confidence_interval_high` | NUMERIC | NULL | 95% confidence upper bound | Statistical calculation | 4000.00 |
| `confidence_interval_low` | NUMERIC | NULL | 95% confidence lower bound | Statistical calculation | 3000.00 |
| `method` | TEXT | NULL | Forecasting algorithm used | Model identifier | "ensemble_linear_exp" |
| `created_at` | TIMESTAMP | NOT NULL | Forecast generation timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `forecast_id`
- Unique: `(month_start, app_id, capability_id, tier)`
- Standard: `month_start`, `app_id`

**Business Rules:**
- Generated by `advanced_forecasting.py` using historical data (90+ days)
- Multiple algorithms: linear regression, exponential smoothing, ensemble
- Confidence intervals represent 95% statistical confidence bands
- Refreshed monthly with latest data

**Forecasting Methodologies:**
1. **Linear Regression**: Trend-based projection using scipy.stats.linregress
2. **Exponential Smoothing**: Time-series smoothing with alpha=0.3
3. **Ensemble**: Weighted average (60% linear, 40% exponential)

---

### chargeback_fact
**Purpose:** Monthly chargeback amounts by department/application

**Primary Key:** `chargeback_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `chargeback_id` | BIGSERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `month_start` | DATE | NOT NULL | Chargeback month start date | First day of month | 2025-10-01 |
| `app_id` | INT | NOT NULL | Foreign key to applications_dim | From license_cost_fact | 5 |
| `h_code` | TEXT | NULL | Cost center code | From applications_dim | "BEV-001" |
| `sector_id` | INT | NOT NULL | Foreign key to sectors_dim | From applications_dim | 2 |
| `owner_id` | INT | NOT NULL | Foreign key to owners_dim | From applications_dim | 3 |
| `usd_amount` | NUMERIC(12,2) | NOT NULL | Total monthly chargeback | **AGGREGATED** (see below) | 45678.90 |
| `chargeback_cycle` | TEXT | NULL | Billing cycle identifier | System or allocation type | "direct" or "allocated_shared_service" |
| `is_finalized` | BOOLEAN | NULL | Chargeback approval status | Manual approval workflow | false |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `chargeback_id`
- Unique: `(month_start, app_id, sector_id)`
- Standard: `month_start`, `sector_id`, `h_code`

**Business Rules:**
- Aggregated from `license_cost_fact` by month/app/sector
- H-code must be populated in ServiceNow for accurate chargeback (PepsiCo responsibility)
- Allocation engine may add shared service costs (chargeback_cycle = 'allocated_*')

**Chargeback Calculation:**
```sql
-- Monthly chargeback aggregation (performed in appd_etl.py)
INSERT INTO chargeback_fact (month_start, app_id, h_code, sector_id, owner_id, usd_amount)
SELECT 
    DATE_TRUNC('month', lcf.ts)::date AS month_start,
    lcf.app_id,
    ad.h_code,
    ad.sector_id,
    ad.owner_id,
    SUM(lcf.usd_cost) AS usd_amount
FROM license_cost_fact lcf
JOIN applications_dim ad ON ad.app_id = lcf.app_id
GROUP BY DATE_TRUNC('month', lcf.ts)::date, lcf.app_id, 
         ad.h_code, ad.sector_id, ad.owner_id;
```

---

## Configuration Tables

### price_config
**Purpose:** Contract-based pricing rules for license types and tiers

**Primary Key:** `price_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `price_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `capability_id` | INT | NOT NULL | Foreign key to capabilities_dim | Contract terms | 1 (APM) |
| `tier` | TEXT | NOT NULL | License tier | Contract terms | "PEAK" |
| `start_date` | DATE | NOT NULL | Pricing effective start date | Contract start date | 2025-01-01 |
| `end_date` | DATE | NULL | Pricing effective end date | Contract end date or NULL | 2025-12-31 |
| `unit_rate` | NUMERIC(10,4) | NOT NULL | Cost per license unit (USD) | Contract pricing | 1.2500 |
| `contract_renewal_date` | DATE | NULL | Contract renewal date | Contract terms | 2026-01-01 |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |

**Indexes:**
- Primary Key: `price_id`
- Composite: `(capability_id, tier)` for cost calculation queries

**Business Rules:**
- Only one active price per capability/tier combination at any given date
- `end_date = NULL` indicates current/ongoing pricing
- Date ranges must not overlap for same capability/tier
- Used by ETL to calculate costs from usage

**Price Application Logic:**
```sql
-- Find applicable price for a given date
SELECT unit_rate 
FROM price_config
WHERE capability_id = 1
  AND tier = 'PEAK'
  AND '2025-10-15' BETWEEN start_date AND COALESCE(end_date, '2025-10-15');
```

---

### allocation_rules
**Purpose:** Cost distribution rules for shared services

**Primary Key:** `rule_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `rule_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `rule_name` | TEXT | NOT NULL | Rule description | Manual configuration | "Platform Services - Proportional" |
| `distribution_method` | TEXT | NOT NULL | Allocation algorithm | Manual configuration | "proportional_usage" or "equal_split" |
| `shared_service_code` | TEXT | NULL | H-code pattern to match | Manual configuration | "PLATFORM" |
| `applies_to_sector_id` | INT | NULL | Target sector (NULL = all) | Manual configuration | NULL |
| `is_active` | BOOLEAN | NULL | Rule enabled flag | Manual configuration | true |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |

**Indexes:**
- Primary Key: `rule_id`

**Business Rules:**
- `distribution_method` options:
  - `proportional_usage`: Allocate by sector usage percentage
  - `equal_split`: Divide equally across sectors
  - `custom_formula`: Custom allocation logic (40% usage, 60% equal)
- Matched against applications by H-code pattern
- Applied by `allocation_engine.py` after cost calculation

**Distribution Methods:**

1. **Proportional Usage**:
   ```
   Sector allocation = (Sector usage / Total usage) × Shared service cost
   ```

2. **Equal Split**:
   ```
   Sector allocation = Shared service cost / Number of active sectors
   ```

3. **Custom Formula** (40% usage, 60% equal):
   ```
   Sector allocation = (0.4 × proportional share) + (0.6 × equal share)
   ```

---

### mapping_overrides
**Purpose:** Manual reconciliation overrides for AppDynamics-ServiceNow linking

**Primary Key:** `override_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `override_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `source_system` | TEXT | NOT NULL | Source system name | Manual entry | "AppDynamics" |
| `source_key` | TEXT | NOT NULL | Source identifier | Manual entry | "Supply Chain Viz" |
| `target_table` | TEXT | NOT NULL | Target table name | Manual entry | "applications_dim" |
| `target_field` | TEXT | NOT NULL | Target field name | Manual entry | "sn_sys_id" |
| `override_value` | TEXT | NOT NULL | Override value | Manual entry | "a1b2c3d4e5f6..." |
| `is_active` | BOOLEAN | NULL | Override enabled flag | Manual entry | true |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |
| `updated_by` | TEXT | NULL | User who created override | Manual entry | "john.smith@pepsico.com" |

**Indexes:**
- Primary Key: `override_id`

**Business Rules:**
- Used when automatic fuzzy matching fails (<80% confidence)
- Data stewards manually specify correct mappings
- Reconciliation engine respects active overrides before fuzzy matching
- Provides audit trail of manual interventions

---

### forecast_models
**Purpose:** Forecasting algorithm configurations and parameters

**Primary Key:** `model_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `model_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `model_name` | TEXT | NOT NULL | Model name | Manual configuration | "Linear Regression - 90 Day" |
| `algorithm` | TEXT | NOT NULL | Algorithm identifier | Manual configuration | "linear_regression" |
| `parameters` | JSONB | NULL | Model hyperparameters | Manual configuration | {"lookback_days": 90, "confidence": 0.95} |
| `is_active` | BOOLEAN | NULL | Model enabled flag | Manual configuration | true |
| `created_at` | TIMESTAMP | NOT NULL | Record creation timestamp | System-generated | 2025-01-15 10:30:00 |
| `updated_at` | TIMESTAMP | NOT NULL | Last update timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `model_id`
- Unique: `model_name`

**Business Rules:**
- Currently unused (placeholder for future multi-model forecasting)
- Will allow A/B testing of forecast algorithms

---

## Audit Tables

### etl_execution_log
**Purpose:** ETL job execution history and monitoring

**Primary Key:** `run_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `run_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `job_name` | TEXT | NOT NULL | ETL job identifier | ETL script | "appd_etl" |
| `started_at` | TIMESTAMP | NULL | Job start timestamp | System-generated | 2025-10-30 14:00:00 |
| `finished_at` | TIMESTAMP | NULL | Job completion timestamp | System-generated | 2025-10-30 14:05:23 |
| `status` | TEXT | NULL | Job status | ETL script | "success" or "failed" |
| `rows_ingested` | INT | NULL | Rows processed | ETL script | 1092 |
| `error_message` | TEXT | NULL | Error details (if failed) | Exception message | NULL |

**Indexes:**
- Primary Key: `run_id`
- Standard: `started_at DESC`, `(job_name, started_at DESC)`

**Business Rules:**
- Logged at start of each ETL job
- Updated on completion (success or failure)
- Used for monitoring and SLA tracking

---

### data_lineage
**Purpose:** Complete audit trail of data changes

**Primary Key:** `lineage_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `lineage_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `run_id` | INT | NULL | Foreign key to etl_execution_log | From ETL job | 5 |
| `source_system` | TEXT | NULL | Source system name | ETL script | "AppDynamics" or "ServiceNow" |
| `source_endpoint` | TEXT | NULL | Source API endpoint | ETL script | "/controller/rest/applications" |
| `target_table` | TEXT | NOT NULL | Target table name | ETL script | "license_usage_fact" |
| `target_pk` | JSONB | NULL | Target record primary key | ETL script | {"usage_id": 1234} |
| `changed_fields` | JSONB | NULL | Modified fields (before/after) | ETL script | {"units_consumed": {"old": 100, "new": 120}} |
| `action` | TEXT | NULL | Action performed | ETL script | "INSERT", "UPDATE", or "DELETE" |
| `created_at` | TIMESTAMP | NOT NULL | Lineage record timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `lineage_id`
- Standard: `run_id`, `target_table`

**Business Rules:**
- Logged by `audit_logger.log_data_lineage()` function
- Provides complete traceability from source to target
- Used for compliance and data quality auditing

---

### reconciliation_log
**Purpose:** AppDynamics-ServiceNow reconciliation history

**Primary Key:** `reconciliation_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `reconciliation_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `match_run_ts` | TIMESTAMP | NULL | Reconciliation run timestamp | System-generated | 2025-10-30 14:22:00 |
| `source_a` | TEXT | NULL | First source system | Reconciliation engine | "AppDynamics" |
| `source_b` | TEXT | NULL | Second source system | Reconciliation engine | "ServiceNow" |
| `match_key_a` | TEXT | NULL | Application name from source A | AppDynamics | "E-Commerce Platform" |
| `match_key_b` | TEXT | NULL | Application name from source B | ServiceNow | "E-Commerce" |
| `confidence_score` | NUMERIC | NULL | Match confidence (0-100) | Fuzzy matching algorithm | 95.5 |
| `match_status` | TEXT | NULL | Match result | Reconciliation engine | "auto_matched" or "needs_review" |
| `resolved_app_id` | INT | NULL | Resulting app_id (if matched) | Foreign key to applications_dim | 5 |

**Indexes:**
- Primary Key: `reconciliation_id`
- Standard: `match_status`

**Business Rules:**
- Match thresholds:
  - ≥80%: Auto-match (automatic linking)
  - 50-79%: Needs review (manual mapping required)
  - <50%: No match logged
- `match_status` values:
  - `auto_matched`: Automatically linked
  - `needs_review`: Manual intervention required
  - `manual_override`: Data steward override applied

**Fuzzy Matching Algorithm:**
```python
# SequenceMatcher ratio (Levenshtein-like similarity)
score = SequenceMatcher(None, name1.lower(), name2.lower()).ratio() * 100
```

---

### user_actions
**Purpose:** Administrative user actions audit log

**Primary Key:** `action_id`

| Column | Type | Null | Description | Source | Example |
|--------|------|------|-------------|--------|---------|
| `action_id` | SERIAL | NOT NULL | Surrogate primary key | System-generated | 1 |
| `user_name` | TEXT | NOT NULL | User identifier | Authentication system | "john.smith@pepsico.com" |
| `action_type` | TEXT | NOT NULL | Action category | Manual/UI action | "price_update" or "manual_mapping" |
| `target_table` | TEXT | NULL | Affected table | Manual/UI action | "price_config" |
| `details` | JSONB | NULL | Action details | Manual/UI action | {"price_id": 3, "old_rate": 1.25, "new_rate": 1.30} |
| `action_ts` | TIMESTAMP | NULL | Action timestamp | System-generated | 2025-10-30 14:22:00 |

**Indexes:**
- Primary Key: `action_id`
- Standard: `action_ts DESC`

**Business Rules:**
- Logged by `audit_logger.log_user_action()` function
- Captures all administrative changes for compliance
- Used for security auditing and change tracking

**Common Action Types:**
- `price_update`: Price configuration changes
- `manual_mapping`: Manual reconciliation override
- `allocation_rule_change`: Shared service allocation rule modification
- `data_correction`: Manual data quality fix

---

## Views

### app_cross_reference_v
**Purpose:** Denormalized application view with match status for dashboards

**Columns:**

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `app_id` | INT | Application ID | 5 |
| `appd_application_id` | INT | AppDynamics ID | 12345 |
| `appd_application_name` | TEXT | AppDynamics name | "E-Commerce Platform" |
| `sn_sys_id` | TEXT | ServiceNow sys_id | "a1b2c3..." |
| `sn_service_name` | TEXT | ServiceNow name | "E-Commerce" |
| `owner_name` | TEXT | Owner name | "Platform Engineering" |
| `sector_name` | TEXT | Sector name | "Beverages North America" |
| `architecture` | TEXT | Architecture pattern | "Microservices" |
| `h_code` | TEXT | Cost center | "BEV-001" |
| `is_critical` | BOOLEAN | Criticality flag | true |
| `support_group` | TEXT | Support team | "Platform Engineering" |
| `match_status` | TEXT | **Derived:** Reconciliation status | "Matched", "AppD Only", "ServiceNow Only" |

**Match Status Logic:**
- "Matched": Both `appd_application_id` AND `sn_sys_id` are populated
- "AppD Only": Only `appd_application_id` is populated
- "ServiceNow Only": Only `sn_sys_id` is populated

**Usage:**
```sql
-- Dashboard query: Show all matched applications
SELECT * FROM app_cross_reference_v WHERE match_status = 'Matched';
```

---

### app_license_summary_v
**Purpose:** Current month license summary by application

**Columns:**

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `app_id` | INT | Application ID | 5 |
| `application_name` | TEXT | Application name (AppD or ServiceNow) | "E-Commerce Platform" |
| `owner_name` | TEXT | Owner name | "Platform Engineering" |
| `sector_name` | TEXT | Sector name | "Beverages North America" |
| `architecture` | TEXT | Architecture pattern | "Microservices" |
| `h_code` | TEXT | Cost center | "BEV-001" |
| `capability_count` | BIGINT | Number of license types used | 2 |
| `total_units_consumed` | NUMERIC | Total units (current month) | 3456.78 |
| `total_cost` | NUMERIC | Total cost (current month) | 12345.67 |

**Aggregation Period:** Current calendar month (`DATE_TRUNC('month', NOW())`)

**Usage:**
```sql
-- Dashboard query: Top 10 applications by cost this month
SELECT * FROM app_license_summary_v 
ORDER BY total_cost DESC 
LIMIT 10;
```

---

### peak_vs_pro_savings_v
**Purpose:** Peak vs Pro tier analysis with savings potential

**Columns:**

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `app_id` | INT | Application ID | 5 |
| `application_name` | TEXT | Application name | "E-Commerce Platform" |
| `sector_name` | TEXT | Sector name | "Beverages North America" |
| `capability_code` | TEXT | License type | "APM" |
| `peak_units` | NUMERIC | Units consumed on Peak tier | 2000.00 |
| `pro_units` | NUMERIC | Units consumed on Pro tier | 1500.00 |
| `peak_cost` | NUMERIC | Cost for Peak tier usage | 8000.00 |
| `pro_cost` | NUMERIC | Cost for Pro tier usage | 4500.00 |
| `potential_savings` | NUMERIC | **Calculated:** Savings if Peak→Pro | 2640.00 |

**Savings Calculation:**
```sql
-- 33% savings assumption (Peak typically costs ~1.5x Pro)
potential_savings = peak_cost × 0.33
```

**Aggregation Period:** Last 3 months

**Usage:**
```sql
-- Dashboard query: Applications with highest downgrade savings potential
SELECT * FROM peak_vs_pro_savings_v 
WHERE peak_units > 0
ORDER BY potential_savings DESC 
LIMIT 20;
```

---

### architecture_efficiency_v
**Purpose:** License efficiency metrics by architecture pattern

**Columns:**

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `architecture` | TEXT | Architecture pattern | "Microservices" |
| `app_count` | BIGINT | Number of applications | 12 |
| `avg_daily_units` | NUMERIC | Average daily units per app | 123.45 |
| `avg_nodes` | NUMERIC | Average nodes per app | 15.0 |
| `efficiency_ratio` | NUMERIC | **Calculated:** Units per node | 8.23 |
| `total_cost` | NUMERIC | Total cost (current month) | 45678.90 |
| `cost_per_app` | NUMERIC | Average cost per application | 3806.58 |

**Efficiency Ratio:**
```sql
efficiency_ratio = avg_daily_units / avg_nodes
-- Lower ratio = more efficient (fewer units per node)
```

**Aggregation Period:** Current calendar month

**Usage:**
```sql
-- Dashboard query: Compare Monolith vs Microservices efficiency
SELECT 
    architecture,
    app_count,
    efficiency_ratio,
    cost_per_app
FROM architecture_efficiency_v
ORDER BY architecture;
```

---

## Calculation Methodologies

### 1. Daily License Cost

**Formula:**
```
Daily Cost (USD) = Units Consumed × Unit Rate
```

**Implementation:**
```sql
SELECT 
    u.ts,
    u.app_id,
    u.capability_id,
    u.tier,
    u.units_consumed,
    p.unit_rate,
    ROUND((u.units_consumed * p.unit_rate)::numeric, 2) AS usd_cost
FROM license_usage_fact u
JOIN price_config p 
    ON u.capability_id = p.capability_id
    AND u.tier = p.tier
    AND u.ts::date BETWEEN p.start_date AND COALESCE(p.end_date, u.ts::date);
```

**Inputs:**
- `units_consumed`: From AppDynamics API (daily usage metrics)
- `unit_rate`: From contract pricing in `price_config` table

**Business Rules:**
- Pricing effective dates must match usage dates
- If multiple price records exist, latest effective price is used
- Costs rounded to 2 decimal places (USD cents)

---

### 2. Monthly Chargeback Amount

**Formula:**
```
Monthly Chargeback = SUM(Daily Costs) for month/app/sector
```

**Implementation:**
```sql
SELECT 
    DATE_TRUNC('month', lcf.ts)::date AS month_start,
    lcf.app_id,
    ad.sector_id,
    ad.h_code,
    SUM(lcf.usd_cost) AS usd_amount
FROM license_cost_fact lcf
JOIN applications_dim ad ON ad.app_id = lcf.app_id
GROUP BY DATE_TRUNC('month', lcf.ts)::date, 
         lcf.app_id, 
         ad.sector_id, 
         ad.h_code;
```

**Aggregation Dimensions:**
- Month (calendar month start date)
- Application (app_id)
- Sector (sector_id for business unit)
- H-code (cost center for financial system integration)

**Business Rules:**
- Aggregated at calendar month boundaries
- H-code must be populated in ServiceNow for accurate allocation
- Shared service allocations added by allocation engine

---

### 3. Forecast Projection (Ensemble Method)

**Formula:**
```
Ensemble Forecast = (0.6 × Linear Projection) + (0.4 × Exponential Smoothing)
```

**Linear Regression Component:**
```python
# scipy.stats.linregress on 90 days of historical usage
slope, intercept = linregress(x=days, y=usage_history)
projection[month] = slope × future_day + intercept
```

**Exponential Smoothing Component:**
```python
# Simple exponential smoothing (alpha=0.3)
smoothed[t] = alpha × actual[t] + (1 - alpha) × smoothed[t-1]
projection[month] = smoothed[last] + trend × months_ahead
```

**Confidence Intervals (95%):**
```python
# Standard error from linear regression
prediction_std = std_err × sqrt(1 + 1/n + (x_future - x_mean)^2 / sum((x - x_mean)^2))
ci_high = projection + 1.96 × prediction_std
ci_low = projection - 1.96 × prediction_std
```

**Inputs:**
- Minimum 30 days of historical usage required
- Uses last 90 days for model training
- Projects 12 months forward

**Business Rules:**
- Forecasts regenerated monthly with latest data
- Applications without sufficient history excluded
- Method identifier stored for audit trail

---

### 4. Shared Service Cost Allocation

**Proportional Usage Method:**
```
Sector Allocation = (Sector Total Usage / All Sectors Usage) × Shared Service Cost
```

**Implementation:**
```sql
WITH sector_usage AS (
    SELECT 
        a.sector_id,
        SUM(u.units_consumed) as sector_usage
    FROM license_usage_fact u
    JOIN applications_dim a ON a.app_id = u.app_id
    WHERE DATE_TRUNC('month', u.ts) = '2025-10-01'
    GROUP BY a.sector_id
),
shared_service_cost AS (
    SELECT SUM(usd_cost) as total_cost
    FROM license_cost_fact
    WHERE app_id = 5  -- Shared service app
      AND DATE_TRUNC('month', ts) = '2025-10-01'
)
SELECT 
    su.sector_id,
    (su.sector_usage / SUM(su.sector_usage) OVER ()) * ssc.total_cost as allocated_amount
FROM sector_usage su
CROSS JOIN shared_service_cost ssc;
```

**Equal Split Method:**
```
Sector Allocation = Shared Service Cost / Number of Active Sectors
```

**Custom Formula (40% Usage, 60% Equal):**
```
Sector Allocation = (0.4 × Proportional Share) + (0.6 × Equal Share)
```

**Business Rules:**
- Shared services identified by H-code patterns (PLATFORM, SHARED, GLOBAL)
- Applied after direct cost calculation
- Stored in `chargeback_fact` with `chargeback_cycle = 'allocated_*'`

---

### 5. Cost Calculation Accuracy Validation

**Formula:**
```
Variance % = |Expected Cost - Actual Cost| / Expected Cost × 100
```

**Expected Cost Calculation:**
```sql
-- Theoretical cost based on usage × pricing
SELECT SUM(u.units_consumed × p.unit_rate) as expected_cost
FROM license_usage_fact u
JOIN price_config p ON u.capability_id = p.capability_id 
    AND u.tier = p.tier;
```

**Actual Cost:**
```sql
-- Stored cost in license_cost_fact
SELECT SUM(usd_cost) as actual_cost
FROM license_cost_fact;
```

**Acceptance Criteria:**
- Variance must be ≤ 2% (SOW requirement)
- Current system achieves 0.00-0.46% variance

---

## Data Lineage

### ETL Data Flow

```
┌─────────────────┐
│  AppDynamics    │ OAuth2 API
│  REST API       │────────────┐
└─────────────────┘            │
                               ▼
┌─────────────────┐     ┌─────────────┐
│  ServiceNow     │────▶│  ETL Engine │
│  CMDB API       │     │  (Python)   │
└─────────────────┘     └─────────────┘
                               │
                ┌──────────────┼──────────────┐
                ▼              ▼              ▼
        ┌─────────────┐ ┌─────────────┐ ┌──────────────┐
        │ Dimension   │ │ Usage Fact  │ │ Reconcile    │
        │ Tables      │ │ Table       │ │ AppD + SNOW  │
        └─────────────┘ └─────────────┘ └──────────────┘
                │              │              │
                ▼              ▼              ▼
        ┌─────────────────────────────────────────┐
        │      Cost Calculation Engine            │
        │  (Usage × Pricing → Cost Fact)          │
        └─────────────────────────────────────────┘
                               │
                ┌──────────────┼──────────────┐
                ▼              ▼              ▼
        ┌─────────────┐ ┌─────────────┐ ┌──────────────┐
        │ Chargeback  │ │ Forecasting │ │ Allocation   │
        │ Aggregation │ │ Engine      │ │ Engine       │
        └─────────────┘ └─────────────┘ └──────────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │  Grafana Dashboards │
                    └─────────────────────┘
```

### Source System Attribution

| Target Table | Primary Source | Secondary Source | Reconciliation Method |
|--------------|----------------|------------------|----------------------|
| `applications_dim` | ServiceNow CMDB | AppDynamics API | Fuzzy name matching |
| `servers_dim` | ServiceNow CMDB | - | Direct extraction |
| `app_server_mapping` | ServiceNow CMDB | - | Relationship table |
| `license_usage_fact` | AppDynamics API | - | Direct extraction |
| `license_cost_fact` | **CALCULATED** | usage_fact + price_config | Join operation |
| `chargeback_fact` | **AGGREGATED** | cost_fact + applications_dim | Monthly grouping |
| `forecast_fact` | **ML MODEL** | usage_fact (90 days) | Statistical projection |

---

## Data Quality Rules

### Mandatory Field Population

| Table | Mandatory Fields | PepsiCo Responsibility |
|-------|------------------|------------------------|
| `applications_dim` | `owner_id`, `sector_id` | ServiceNow: Populate owned_by, u_sector |
| `applications_dim` | `h_code` (**90% target**) | ServiceNow: Populate u_h_code/cost_center |
| `license_usage_fact` | `units_consumed`, `tier` | AppDynamics: Ensure license reporting enabled |
| `price_config` | `unit_rate`, effective dates | Manual: Update pricing from contracts |

### Data Freshness SLAs

| Process | Frequency | Acceptable Lag | Monitoring |
|---------|-----------|----------------|------------|
| ServiceNow ETL | Daily 2 AM | < 6 hours | `etl_execution_log` |
| AppDynamics ETL | Daily 2 AM | < 6 hours | `etl_execution_log` |
| Reconciliation | Daily 2:15 AM | < 30 minutes | `reconciliation_log` |
| Cost Calculation | Daily 2:20 AM | < 30 minutes | `license_cost_fact.created_at` |
| Forecasting | Monthly (1st) | < 24 hours | `forecast_fact.created_at` |
| Chargeback Close | Monthly (5th) | < 48 hours | `chargeback_fact.is_finalized` |

### Orphan Record Detection

```sql
-- Detect usage records without corresponding costs
SELECT COUNT(*) as orphaned_usage
FROM license_usage_fact u
LEFT JOIN license_cost_fact c 
    ON c.ts = u.ts 
    AND c.app_id = u.app_id
    AND c.capability_id = u.capability_id
    AND c.tier = u.tier
WHERE c.cost_id IS NULL;

-- Expected result: 0 rows
```

---

## Appendix: Common Queries

### Executive Summary (Current Month)

```sql
SELECT 
    COUNT(DISTINCT ad.app_id) as total_applications,
    COUNT(DISTINCT ad.app_id) FILTER (WHERE ad.appd_application_id IS NOT NULL) as monitored_apps,
    COUNT(DISTINCT s.sector_id) as active_sectors,
    SUM(lcf.usd_cost) as current_month_cost,
    SUM(ff.projected_cost) as next_month_forecast
FROM applications_dim ad
LEFT JOIN license_cost_fact lcf 
    ON lcf.app_id = ad.app_id 
    AND DATE_TRUNC('month', lcf.ts) = DATE_TRUNC('month', NOW())
LEFT JOIN forecast_fact ff 
    ON ff.app_id = ad.app_id 
    AND ff.month_start = DATE_TRUNC('month', NOW() + INTERVAL '1 month')
LEFT JOIN sectors_dim s ON s.sector_id = ad.sector_id;
```

### Top Cost Drivers (Last 3 Months)

```sql
SELECT 
    COALESCE(ad.appd_application_name, ad.sn_service_name) as application,
    s.sector_name,
    cd.capability_code,
    SUM(lcf.usd_cost) as total_cost,
    AVG(lcf.usd_cost) as avg_daily_cost
FROM license_cost_fact lcf
JOIN applications_dim ad ON ad.app_id = lcf.app_id
JOIN sectors_dim s ON s.sector_id = ad.sector_id
JOIN capabilities_dim cd ON cd.capability_id = lcf.capability_id
WHERE lcf.ts >= NOW() - INTERVAL '3 months'
GROUP BY ad.appd_application_name, ad.sn_service_name, s.sector_name, cd.capability_code
ORDER BY total_cost DESC
LIMIT 20;
```

### Chargeback Invoice (Specific Month/Sector)

```sql
SELECT 
    cf.h_code,
    COALESCE(ad.appd_application_name, ad.sn_service_name) as application,
    o.owner_name,
    cf.usd_amount,
    cf.chargeback_cycle,
    cf.is_finalized
FROM chargeback_fact cf
JOIN applications_dim ad ON ad.app_id = cf.app_id
JOIN owners_dim o ON o.owner_id = cf.owner_id
JOIN sectors_dim s ON s.sector_id = cf.sector_id
WHERE cf.month_start = '2025-10-01'
  AND s.sector_name = 'Beverages North America'
ORDER BY cf.usd_amount DESC;
```

---

**Document Version:** 1.0  
**Last Updated:** October 30, 2025  
**Maintained By:** CDW Data Engineering Team  
**Contact:** data-engineering@cdw.com