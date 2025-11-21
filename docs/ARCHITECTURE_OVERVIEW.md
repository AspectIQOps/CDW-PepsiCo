# PepsiCo AppDynamics Analytics Platform - Architecture Overview

**Date:** 2025-11-21
**Purpose:** High-level guide explaining how all the pieces fit together

---

## 🎯 What This Platform Does

**In One Sentence:**
Pulls license usage data from AppDynamics, enriches it with ServiceNow business context, calculates costs, generates forecasts, and displays everything in 8 interactive Grafana dashboards.

**Business Value:**
- Track $XXM+ annual AppDynamics spend
- Chargeback costs to departments by H-code
- Forecast future license needs (12/18/24 months)
- Identify optimization opportunities (Peak vs Pro, monolith efficiency)

---

## 🏗️ Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES (External APIs)               │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌──────────────────────┐        ┌──────────────────────┐          │
│  │  AppDynamics SaaS    │        │  ServiceNow CMDB     │          │
│  │  (3 Controllers)     │        │  (Pre-Production)    │          │
│  │                      │        │                      │          │
│  │  • Applications      │        │  • App Owners        │          │
│  │  • Nodes & Tiers     │        │  • Sectors           │          │
│  │  • License Usage     │        │  • Business Units    │          │
│  │  • H-code Tags       │        │  • Server Relations  │          │
│  └──────────┬───────────┘        └──────────┬───────────┘          │
│             │                               │                      │
│             │ OAuth 2.0                     │ OAuth 2.0            │
│             │                               │                      │
└─────────────┼───────────────────────────────┼──────────────────────┘
              │                               │
              ▼                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ETL PIPELINE (Docker Container)                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Phase 1: AppDynamics Extract   ───────────┐                        │
│    • Fetch apps, nodes, tiers              │                        │
│    • Pull license usage data               │                        │
│    • Extract H-codes from tags             │                        │
│    • Calculate costs from usage            │                        │
│                                            │                        │
│  Phase 2: ServiceNow Enrichment  ───────┐  │                        │
│    • Match apps to CMDB records         │  │                        │
│    • Add owner, sector, BU info         │  │                        │
│    • Link servers to applications       │  │                        │
│                                         │  │                        │
│  Phase 3: Finalization            ───┐  │  │                        │
│    • Shared service allocation       │  │  │                        │
│    • Advanced forecasting            │  │  │                        │
│    • Refresh materialized views      │  │  │                        │
│                                      │  │  │                        │
│  ┌──────────────┐  ┌─────────────┐   │  │  │                        │
│  │ run_pipeline │─▶│ ETL Scripts │◀──┴──┴──┘                        │
│  │    .py       │  └─────────────┘                                  │
│  └──────────────┘        │                                          │
│                          │ Writes to                                │
│                          ▼                                          │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    DATABASE (PostgreSQL)                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  STAR SCHEMA:                                                       │
│                                                                     │
│  Dimensions (Who/What/Where):        Facts (Metrics):              │
│  ┌──────────────────────┐           ┌──────────────────────┐      │
│  │ applications_dim     │           │ license_usage_fact   │      │
│  │ • app_id (PK)        │           │ • date, app_id       │      │
│  │ • name, h_code       │           │ • capability, tier   │      │
│  │ • architecture       │           │ • units_consumed     │      │
│  └──────────────────────┘           └──────────────────────┘      │
│                                                                     │
│  ┌──────────────────────┐           ┌──────────────────────┐      │
│  │ nodes_dim            │           │ license_cost_fact    │      │
│  │ tiers_dim            │           │ • date, app_id       │      │
│  │ controllers_dim      │           │ • cost_usd           │      │
│  │ capabilities_dim     │           │ • price_per_unit     │      │
│  └──────────────────────┘           └──────────────────────┘      │
│                                                                     │
│  MATERIALIZED VIEWS (Performance):                                 │
│  • mv_daily_cost_by_controller    (180 days)                       │
│  • mv_daily_usage_by_capability   (180 days)                       │
│  • mv_cost_by_sector_controller   (Chargeback)                     │
│  • mv_architecture_metrics_90d    (Efficiency)                     │
│  • mv_peak_pro_comparison         (Savings analysis)               │
│  • mv_app_cost_rankings_monthly   (Top consumers)                  │
│  • mv_monthly_chargeback_summary  (Billing)                        │
│  • mv_cost_by_owner_controller    (By owner)                       │
│                                                                     │
│  Refresh: < 2 minutes | Query: < 5 seconds                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            │ Read-Only Access (grafana_ro user)
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    DASHBOARDS (Grafana)                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  8 Interactive Dashboards:                                          │
│                                                                     │
│  1. 📊 Executive Overview                                           │
│     • Monthly KPIs (total cost, usage, apps)                        │
│     • Top 10 cost consumers                                         │
│     • Cost trends over time                                         │
│                                                                     │
│  2. 📱 Usage by License Type                                        │
│     • APM, Mobile RUM, Browser RUM, Synthetic, DB, Infrastructure   │
│     • Usage trends by capability                                    │
│     • License type distribution                                     │
│                                                                     │
│  3. 💰 Cost Analytics                                               │
│     • Multi-dimensional analysis (sector, owner, app, tier)         │
│     • Cost breakdown by controller                                  │
│     • Custom time ranges via picker                                 │
│                                                                     │
│  4. ⚖️  Peak vs Pro Analysis                                        │
│     • Peak vs Pro usage comparison                                  │
│     • Savings potential if switching tiers                          │
│     • Cost efficiency metrics                                       │
│                                                                     │
│  5. 🏛️  Architecture Analysis                                       │
│     • Monolith vs Microservices efficiency                          │
│     • Node-per-application ratios                                   │
│     • Architecture recommendations                                  │
│                                                                     │
│  6. 📈 Trends & Forecasts                                           │
│     • 24-month historical trends                                    │
│     • 12/18/24-month usage forecasts                                │
│     • Linear regression projections                                 │
│                                                                     │
│  7. 🧾 Allocation & Chargeback                                      │
│     • Department-level charges by H-code                            │
│     • Shared service cost allocation                                │
│     • Monthly billing summaries                                     │
│                                                                     │
│  8. 🔧 Admin Panel                                                  │
│     • ETL execution logs                                            │
│     • Data quality metrics (H-code coverage)                        │
│     • Pipeline status monitoring                                    │
│                                                                     │
│  Performance: <5 seconds per dashboard load                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Repository Structure

```
CDW-PepsiCo/
│
├── scripts/                    # All Python ETL scripts
│   ├── etl/
│   │   ├── run_pipeline.py    # Main orchestrator (runs all phases)
│   │   ├── appd_extract.py    # Phase 1: Pull AppDynamics data
│   │   ├── snow_enrichment.py # Phase 2: Add ServiceNow context
│   │   └── appd_finalize.py   # Phase 3: Allocations & forecasts
│   │
│   ├── setup/
│   │   └── init_database.sh   # Initialize PostgreSQL schema
│   │
│   └── utils/                  # Test & diagnostic scripts
│       ├── test_all_prod_controllers.sh   # Test PROD API access
│       ├── test_prod_licensing_api.sh     # Test single controller
│       └── gemini.sh                      # SOW compliance validation
│
├── sql/                        # Database schema & setup
│   └── schema.sql             # Star schema, materialized views, functions
│
├── config/                     # Configuration files
│   └── grafana/
│       └── dashboards/
│           └── final/         # 8 Grafana dashboard JSON files
│
├── docker/                     # Docker build files
│   └── etl/
│       ├── Dockerfile         # ETL container image
│       └── entrypoint.sh      # Load secrets from AWS SSM
│
├── docker-compose.yaml         # Container orchestration
│
└── docs/                       # Documentation
    ├── ARCHITECTURE_OVERVIEW.md          # This file
    ├── CLIENT_REQUIREMENTS_SIMPLE.md     # What we need from client
    ├── SOW_COMPLIANCE_VERIFIED.txt       # Compliance verification
    ├── REAL_VS_MOCK_DATA_BREAKDOWN.md    # Data source details
    └── DEPLOYMENT_GUIDE.md               # How to deploy
```

---

## 🔄 How Data Flows (Step-by-Step)

### **1. ETL Pipeline Execution**

```bash
# Run via Docker Compose
docker-compose up etl-analytics

# Or directly
python3 scripts/etl/run_pipeline.py
```

### **2. Phase 1: AppDynamics Extract** (appd_extract.py)

**What it does:**
- Connects to 3 AppDynamics controllers via OAuth 2.0
- Pulls application inventory (apps, nodes, tiers)
- Fetches license usage data (Licensing API v1)
- Extracts H-code tags from application properties
- Calculates costs from usage × per-unit pricing

**APIs Called:**
- `POST /controller/api/oauth/access_token` (Auth)
- `GET /controller/rest/applications` (App list)
- `GET /controller/rest/applications/{id}/nodes` (Node details)
- `GET /controller/rest/applications/{id}/tiers` (Tier details)
- `GET /controller/licensing/v1/usage/account/{id}` (License usage) ⚠️ Needs "License Admin"
- `GET /controller/restui/applicationManagerUiBean/applicationDetail` (H-codes)

**Database Tables Written:**
- `controllers_dim` (Controller metadata)
- `applications_dim` (Application inventory)
- `nodes_dim` (Infrastructure nodes)
- `tiers_dim` (Application tiers)
- `license_usage_fact` (Usage metrics)
- `license_cost_fact` (Cost calculations)

**Time:** ~10 minutes for 3 controllers, 216 apps

---

### **3. Phase 2: ServiceNow Enrichment** (snow_enrichment.py)

**What it does:**
- Connects to ServiceNow CMDB via OAuth 2.0
- Matches AppDynamics apps to CMDB records (fuzzy matching)
- Enriches applications with owner, sector, business unit
- Links servers to applications

**APIs Called:**
- `GET /api/now/table/cmdb_ci_appl` (Applications)
- `GET /api/now/table/cmdb_ci_server` (Servers)
- `GET /api/now/table/sys_user` (User details for owners)

**Database Tables Updated:**
- `applications_dim` (Add owner, sector, business unit)
- `application_matches` (Store CMDB reconciliation results)

**Time:** ~5 minutes for 216 apps

---

### **4. Phase 3: Finalization** (appd_finalize.py)

**What it does:**
- Allocates shared service costs across consuming apps
- Generates 12/18/24-month forecasts (linear regression)
- Refreshes 8 materialized views for dashboard performance

**Database Tables Written:**
- `shared_service_allocations` (Cost distributions)
- `advanced_forecasts` (Future usage projections)

**Materialized Views Refreshed:**
- All 8 views (mv_*) rebuilt with latest data

**Time:** ~2 minutes

---

### **5. Dashboards Display Data** (Grafana)

**What happens:**
- Users open Grafana dashboards
- Dashboards query materialized views (pre-aggregated for speed)
- Results return in <5 seconds (SOW requirement)
- Interactive filters update all panels dynamically

**User Actions:**
- Change time range (time picker)
- Filter by controller, sector, owner
- Drill down from summary to detail
- Export data as CSV

---

## 🔐 Security & Secrets Management

### **Secrets Storage:**

All credentials stored in **AWS Systems Manager Parameter Store**:

```
/pepsico/
├── database/
│   ├── host
│   ├── port
│   ├── name
│   ├── user
│   └── password
│
├── appdynamics/
│   ├── controllers           (comma-separated list)
│   ├── accounts              (comma-separated list)
│   ├── client_ids            (comma-separated list)
│   ├── client_secrets        (comma-separated list - encrypted)
│   └── account_ids           (comma-separated list)
│
└── servicenow/
    ├── instance              (e.g., pepsico.service-now.com)
    ├── client_id
    └── client_secret         (encrypted)
```

### **Access Control:**

- **ETL Container:** AWS IAM role with SSM read access
- **Grafana:** Read-only database user (`grafana_ro`)
- **AppDynamics API:** OAuth 2.0 client credentials
- **ServiceNow API:** OAuth 2.0 client credentials

### **No Hardcoded Credentials:**
- All secrets fetched at runtime
- Environment variables loaded from SSM
- Containers destroyed after ETL run

---

## 📊 Database Schema (Star Schema)

### **Dimension Tables (Who/What/Where):**

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `applications_dim` | Application catalog | app_id, name, h_code, architecture |
| `nodes_dim` | Infrastructure nodes | node_id, app_id, node_name, agent_type |
| `tiers_dim` | Application tiers | tier_id, app_id, tier_name, node_count |
| `controllers_dim` | AppD controllers | controller_id, hostname, region |
| `capabilities_dim` | License types | capability_id, code (APM, MRUM, etc.) |

### **Fact Tables (Metrics):**

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `license_usage_fact` | Usage metrics | date, app_id, capability_id, units_consumed |
| `license_cost_fact` | Cost calculations | date, app_id, capability_id, cost_usd |

### **Materialized Views (Performance):**

Pre-aggregated views for <5 second dashboard queries:

- `mv_daily_cost_by_controller` - Daily cost rollups
- `mv_daily_usage_by_capability` - Usage by license type
- `mv_cost_by_sector_controller` - Chargeback by sector
- `mv_cost_by_owner_controller` - Chargeback by owner
- `mv_architecture_metrics_90d` - Monolith vs microservices
- `mv_app_cost_rankings_monthly` - Top consumers
- `mv_monthly_chargeback_summary` - Monthly billing
- `mv_peak_pro_comparison` - Peak vs Pro savings

**Refresh:** Automated at end of ETL pipeline, <2 minutes

---

## ⚙️ Key Components Explained

### **1. Docker Container (etl-analytics)**

**What:** Isolated Python environment running the ETL pipeline

**Configuration:**
- Image: Built from `docker/etl/Dockerfile`
- Base: Python 3.12 slim
- Volumes: Mounts scripts, SQL, logs
- Network: Isolated `analytics-network`
- Entrypoint: Loads secrets from AWS SSM

**Environment Variables:**
- `PIPELINE_MODE`: full | appd-only | snow-only | finalize-only
- `LOG_LEVEL`: INFO | DEBUG | WARNING
- `DRY_RUN`: true | false (test without writing)

**Usage:**
```bash
# Full pipeline
docker-compose up etl-analytics

# AppDynamics only
PIPELINE_MODE=appd-only docker-compose up etl-analytics

# Test mode (no writes)
DRY_RUN=true docker-compose up etl-analytics
```

---

### **2. ETL Scripts**

#### **run_pipeline.py** (Orchestrator)
**Purpose:** Main ETL orchestrator - runs all 7 phases in sequence

**What it does:**
- Validates credentials before starting (AppDynamics, ServiceNow, Database)
- Executes phases 1-7 with retry logic and error handling
- Logs to stdout (Docker-friendly)
- Tracks execution in `etl_execution_log` table
- Handles transient errors (network, timeout) with automatic retries
- Continues on non-critical errors (e.g., ServiceNow unavailable)
- Aborts on critical errors (e.g., AppDynamics unavailable)

**Configuration:**
- `MAX_RETRIES`: 3 attempts for transient failures
- `RETRY_DELAY`: 5 seconds between retries
- Critical phases: 1 (AppD), 3 (finalize), 4 (chargeback)
- Optional phases: 2 (ServiceNow), 5 (allocation), 6 (forecasting), 7 (views)

**Runtime:** ~30 minutes for full pipeline with 3 controllers, 216 apps

---

#### **appd_extract.py** (Phase 1: AppDynamics Core Data Extract)
**Purpose:** Foundation phase - pulls all AppDynamics data

**What it does:**
- Connects to 3 AppDynamics controllers via OAuth 2.0
- Pulls application inventory (apps, nodes, tiers)
- Fetches license usage data from Licensing API v1
- Extracts H-code tags from application custom properties
- Calculates costs: `usage_units × per_unit_pricing`
- Mock data fallback if Licensing API unavailable (demo mode)
- Generates 12 months historical data (365 days per SOW)

**APIs Called:**
- `POST /controller/api/oauth/access_token` - OAuth authentication
- `GET /controller/api/accounts/myaccount` - Account ID discovery
- `GET /controller/rest/applications` - Application list
- `GET /controller/rest/applications/{id}/nodes` - Node details
- `GET /controller/rest/applications/{id}/tiers` - Tier details
- `GET /controller/licensing/v1/usage/account/{id}` - License usage (needs "License Admin" role)
- `GET /controller/restui/applicationManagerUiBean/applicationDetail` - H-codes

**Database Tables Written:**
- `controllers_dim` - Controller metadata (hostname, region)
- `applications_dim` - Application catalog (name, H-code, architecture)
- `nodes_dim` - Infrastructure nodes (agent types, properties)
- `tiers_dim` - Application tiers (node counts)
- `license_usage_fact` - Usage metrics (units consumed per day/app/capability)
- `license_cost_fact` - Cost calculations (USD cost per day/app/capability)

**Architecture Classification:**
- Monolith: Single tier with multiple nodes
- Microservices: Multiple tiers (>3) with distributed nodes
- Uses tier count and node distribution patterns

**Mock Data Generation (Demo Mode):**
- Triggered if Licensing API returns 403/500
- Generates realistic usage patterns based on node counts
- Assigns Peak/Pro tiers based on application size
- Creates 12 months of daily usage records
- Displays prominent warning banners

**Runtime:** ~10 minutes for 3 controllers, 216 apps

---

#### **snow_enrichment.py** (Phase 2: ServiceNow CMDB Enrichment)
**Purpose:** Enrich applications with business context from ServiceNow

**What it does:**
- Connects to ServiceNow CMDB via OAuth 2.0
- Matches AppDynamics apps to CMDB CI records (fuzzy matching)
- Enriches applications with owner, sector, business unit
- Links servers to applications for infrastructure tracking
- Caches CMDB lookups to minimize API calls
- Skips gracefully if ServiceNow credentials not configured

**APIs Called:**
- `GET /api/now/table/cmdb_ci_appl` - Application CIs
- `GET /api/now/table/cmdb_ci_server` - Server CIs
- `GET /api/now/table/sys_user` - User details (for owner lookups)

**Matching Algorithm:**
- Primary: Exact match on application name
- Secondary: Fuzzy match (80% confidence threshold using difflib)
- Stores match confidence score in `application_matches` table
- Manual review possible for low-confidence matches

**Database Tables Updated:**
- `applications_dim` - Adds `sn_sys_id`, `owner_id`, `sector_id`, `business_unit`
- `application_matches` - Stores reconciliation results and confidence scores

**Why It's Optional:**
- Not critical for basic license reporting
- Required for full chargeback by department/owner
- System continues if ServiceNow unavailable

**Runtime:** ~5 minutes for 216 apps

---

#### **appd_finalize.py** (Phase 3: Cost Calculations & Finalization)
**Purpose:** Calculate costs and generate chargeback records

**What it does:**
- Generates monthly chargeback records from daily cost data
- Aggregates costs by month, app, sector, H-code
- Validates H-code coverage and reports gaps
- Inserts into `chargeback_fact` table with 'direct' chargeback cycle
- Reports H-code coverage percentage (SOW requires >90%)

**Cost Calculation:**
- Reads `license_usage_fact` (daily units consumed)
- Joins with `pricing_tiers` table (per-unit pricing)
- Calculates: `units × price_per_unit = usd_cost`
- Aggregates by month for chargeback reporting

**Database Tables Written:**
- `chargeback_fact` - Monthly chargeback by app/sector/h-code

**Data Quality Checks:**
- Reports apps with H-codes vs without
- Calculates H-code coverage percentage
- Warns if coverage below 90%

**Why It's Critical:**
- Required for all cost-related dashboards
- Foundation for chargeback reports
- Enables department-level cost allocation

**Runtime:** ~2 minutes

---

#### **chargeback_calculation.py** (Phase 4: Monthly Chargeback Aggregation)
**Purpose:** Aggregate daily costs into monthly chargeback records

**What it does:**
- Reads daily `license_cost_fact` records
- Aggregates by month + app + sector + H-code
- Inserts into `chargeback_fact` with 'direct' cycle type
- Validates coverage and reports gaps
- Provides month-by-month processing status

**Aggregation Logic:**
```sql
SUM(daily_cost) GROUP BY month, app_id, sector_id, h_code
```

**Database Tables Written:**
- `chargeback_fact` - Monthly aggregated charges

**Conflict Handling:**
- Uses `ON CONFLICT DO UPDATE` for idempotency
- Safe to re-run without duplicates

**Runtime:** ~1 minute

---

#### **allocation_engine.py** (Phase 5: Shared Service Cost Allocation)
**Purpose:** Distribute shared/platform service costs across business sectors

**What it does:**
- Identifies applications tagged as shared services
- Applies allocation rules (proportional, equal split, custom formula)
- Distributes costs based on consumption patterns
- Updates `chargeback_fact` with 'allocated' cycle type

**Identification Criteria:**
- Apps in "Corporate/Shared Services" or "Global IT" sectors
- H-codes containing "PLATFORM", "SHARED", or "GLOBAL"
- Manual tagging in ServiceNow CMDB

**Allocation Methods:**
1. **Proportional Usage** - Distribute based on consuming sector's usage
2. **Equal Split** - Divide equally across all sectors
3. **Custom Formula** - Configurable business rules

**Database Tables:**
- Reads: `applications_dim`, `chargeback_fact`
- Writes: `shared_service_allocations`, updates `chargeback_fact`

**Why It's Optional:**
- Only runs if shared services exist
- Requires ServiceNow enrichment for sector data
- Not critical if no shared infrastructure

**Runtime:** ~2 minutes (if shared services exist)

---

#### **advanced_forecasting.py** (Phase 6: Advanced Forecasting)
**Purpose:** Generate 12/18/24-month usage forecasts using multiple algorithms

**What it does:**
- Pulls historical usage data (minimum 7 days required)
- Applies multiple forecasting algorithms:
  - **Linear Regression** - Trend-based projection
  - **Exponential Smoothing** - Weighted moving average
  - **Ensemble Method** - Combined (60% linear + 40% exponential)
- Generates confidence intervals (95% CI)
- Creates forecasts for 12, 18, and 24 months
- Stores projections in `advanced_forecasts` table

**Algorithms:**

**1. Linear Regression:**
- Uses scipy.stats.linregress
- Calculates slope, intercept, R-squared
- Provides prediction intervals

**2. Exponential Smoothing:**
- Alpha = 0.3 (smoothing factor)
- Captures recent trends
- Good for volatile usage patterns

**3. Ensemble (Recommended):**
- Combines both methods
- More robust against outliers
- Better accuracy than either alone

**Database Tables:**
- Reads: `license_usage_fact` (historical data)
- Writes: `advanced_forecasts` (projections)

**Data Quality:**
- Validates sufficient historical data (7+ days)
- Skips apps with constant zero usage
- Reports insufficient data warnings

**Runtime:** ~2-3 minutes for 216 apps

---

#### **refresh_views.py** (Phase 7: Refresh Dashboard Views)
**Purpose:** Refresh materialized views for <5 second dashboard performance

**What it does:**
- Refreshes all 8 materialized views in priority order
- Uses `REFRESH MATERIALIZED VIEW CONCURRENTLY` where possible
- Falls back to regular refresh if no unique index
- Reports row counts before/after refresh
- Updates PostgreSQL statistics for query planner

**Materialized Views Refreshed:**
1. `mv_daily_cost_by_controller` - Daily cost aggregations (180 days)
2. `mv_daily_usage_by_capability` - Usage by license type (180 days)
3. `mv_cost_by_sector_controller` - Sector cost rollups (180 days)
4. `mv_cost_by_owner_controller` - Owner cost rollups (180 days)
5. `mv_architecture_metrics_90d` - Architecture efficiency (90 days)
6. `mv_app_cost_rankings_monthly` - Monthly rankings (all months)
7. `mv_monthly_chargeback_summary` - Chargeback aggregations (all months)
8. `mv_peak_pro_comparison` - Peak vs Pro analysis (90 days)

**Concurrent vs Regular Refresh:**
- **Concurrent:** Zero downtime, requires unique index, slower
- **Regular:** Locks view briefly, faster, no index required
- Script auto-detects and uses appropriate method

**Performance:**
- Total refresh time: <2 minutes for all 8 views
- Dashboard queries hit views (not base tables)
- Achieves <5 second dashboard load (SOW requirement)

**Runtime:** ~1-2 minutes

---

### **3. PostgreSQL Database**

**Schema:** Deployed via `sql/schema.sql`

**Key Features:**
- Star schema for analytical queries
- Unique constraints prevent duplicates
- `ON CONFLICT DO NOTHING` for idempotency
- Foreign keys maintain referential integrity
- Materialized views for performance

**Users:**
- `pepsico_admin` - Full access (ETL writes)
- `grafana_ro` - Read-only (dashboard queries)

**Maintenance:**
```sql
-- Refresh all views
SELECT refresh_all_materialized_views();

-- Check data quality
SELECT * FROM data_quality_summary;

-- View ETL history
SELECT * FROM etl_execution_log ORDER BY started_at DESC LIMIT 10;
```

---

### **4. Grafana Dashboards**

**Provisioning:** JSON files in `config/grafana/dashboards/final/`

**Key Features:**
- Time picker variables (`$__timeFrom`, `$__timeTo`)
- Multi-select filters (controller, sector, owner)
- Drill-through links between dashboards
- CSV export capability
- Auto-refresh every 5 minutes

**Performance:**
- All queries hit materialized views
- Complex aggregations pre-computed
- <5 second load time (SOW requirement)

---

## 🚀 How to Run the System

### **Prerequisites:**
1. AWS credentials configured (`~/.aws/credentials`)
2. Secrets populated in AWS SSM Parameter Store
3. PostgreSQL database accessible
4. Docker & Docker Compose installed

### **One-Time Setup:**

```bash
# 1. Initialize database schema
./scripts/setup/init_database.sh

# 2. Populate AWS SSM with credentials
# (Manual step - use AWS Console or CLI)
```

### **Daily/Weekly ETL Run:**

```bash
# Run full pipeline
docker-compose up etl-analytics

# View logs
docker-compose logs -f etl-analytics

# Check status
docker-compose ps
```

### **Grafana Access:**

```
URL: http://localhost:3000 (or production URL)
Default User: admin
Default Pass: (configured during Grafana setup)
```

---

## 🔍 Monitoring & Troubleshooting

### **ETL Status:**

**Check execution log:**
```sql
SELECT run_id, phase, status, rows_ingested, started_at, finished_at
FROM etl_execution_log
WHERE started_at > NOW() - INTERVAL '7 days'
ORDER BY started_at DESC;
```

**Check for errors:**
```bash
docker-compose logs etl-analytics | grep "ERROR\|CRITICAL"
```

### **Data Quality:**

**H-code coverage:**
```sql
SELECT
  COUNT(*) FILTER (WHERE h_code IS NOT NULL) * 100.0 / COUNT(*) AS h_code_coverage_pct
FROM applications_dim;
```

**Usage data freshness:**
```sql
SELECT MAX(usage_date) AS last_usage_date
FROM license_usage_fact;
```

### **Performance:**

**Dashboard query time:**
- Grafana → Dashboard → Settings → Query inspector
- Should be <5 seconds per panel

**Materialized view refresh time:**
```sql
SELECT * FROM refresh_all_materialized_views();
-- Should complete in <2 minutes
```

---

## 📈 Data Volumes

### **Current (TEST Environment):**
- Applications: 128
- Nodes: 400+
- Tiers: 800+
- Usage records: 93,440 (12 months × 128 apps × ~2 capabilities)
- Cost records: 93,440

### **Production (Expected):**
- Applications: 216+
- Nodes: 600+ (estimated)
- Usage records: 550,000+ (real API data)
- Cost records: 550,000+

### **Database Size:**
- Current: ~500 MB
- Production: ~2-3 GB (estimated)
- Materialized views: ~100 MB additional

---

## 🎯 Key Performance Indicators

| Metric | Target | Current Status |
|--------|--------|----------------|
| Dashboard load time | <5 seconds | ✅ 3-4 seconds |
| ETL runtime (full) | <60 minutes | ✅ ~30 minutes |
| Materialized view refresh | <5 minutes | ✅ <2 minutes |
| H-code coverage | >90% | ⚠️ ~20% (client must tag) |
| Data freshness | Daily | ✅ On-demand ETL |
| Forecast horizon | 24 months | ✅ 12/18/24 months |

---

## 🔧 Configuration

### **ETL Customization:**

**Change historical data window:**
```python
# scripts/etl/appd_extract.py line 584
start_date = now - timedelta(days=365)  # Change 365 to desired days
```

**Adjust pricing:**
```sql
-- Update pricing table
UPDATE pricing_tiers
SET price_per_unit = 85.00
WHERE capability_code = 'APM' AND tier = 'Peak';
```

**Add new controllers:**
```bash
# Update AWS SSM parameters
aws ssm put-parameter \
  --name /pepsico/appdynamics/controllers \
  --value "controller1,controller2,controller3,controller4" \
  --overwrite
```

---

## 📞 Support & Maintenance

### **Common Tasks:**

| Task | Command |
|------|---------|
| Run ETL pipeline | `docker-compose up etl-analytics` |
| View logs | `docker-compose logs -f etl-analytics` |
| Refresh dashboards | `SELECT refresh_all_materialized_views();` |
| Test API access | `./scripts/utils/test_all_prod_controllers.sh` |
| Verify SOW compliance | `./scripts/utils/gemini.sh` |
| Initialize database | `./scripts/setup/init_database.sh` |

### **Backup & Recovery:**

**Database backup:**
```bash
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME > backup.sql
```

**Restore:**
```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME < backup.sql
```

---

## ✅ Quick Health Check

**Is everything working?**

1. ✅ ETL runs without errors
2. ✅ Database has recent usage data (last 24 hours)
3. ✅ All 8 dashboards load in <5 seconds
4. ✅ Materialized views refresh in <2 minutes
5. ✅ H-code coverage reported in Admin Panel
6. ✅ Forecasts generated for all applications

**If any fail, check:**
- Docker logs: `docker-compose logs`
- Database connectivity: `psql -h $DB_HOST`
- AWS SSM access: `aws ssm get-parameter --name /pepsico/database/host`
- API permissions: `./scripts/utils/test_all_prod_controllers.sh`

---

## 📚 Additional Documentation

For detailed information, see:

- **[CLIENT_REQUIREMENTS_SIMPLE.md](CLIENT_REQUIREMENTS_SIMPLE.md)** - What we need from client
- **[SOW_COMPLIANCE_VERIFIED.txt](SOW_COMPLIANCE_VERIFIED.txt)** - Compliance verification
- **[REAL_VS_MOCK_DATA_BREAKDOWN.md](REAL_VS_MOCK_DATA_BREAKDOWN.md)** - Data sources explained
- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Deployment instructions
- **[DEMO_PIPELINE_STATUS.md](DEMO_PIPELINE_STATUS.md)** - Demo readiness

---

**Last Updated:** 2025-11-21
**Platform Version:** v1.0 MVP
**Status:** ✅ Production-ready (pending client permissions)
