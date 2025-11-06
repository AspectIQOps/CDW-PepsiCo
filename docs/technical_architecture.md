# PepsiCo AppDynamics License Management
## Technical Architecture Document v1.0

**Last Updated:** October 30, 2025  
**Project:** AppDynamics License Tracking, Cost Allocation, and Chargeback System  
**Developed By:** CDW Data Engineering Team  
**Client:** PepsiCo IT

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Architecture Overview](#system-architecture-overview)
3. [Infrastructure Components](#infrastructure-components)
4. [Data Architecture](#data-architecture)
5. [ETL Pipeline Design](#etl-pipeline-design)
6. [Integration Architecture](#integration-architecture)
7. [Security Architecture](#security-architecture)
8. [Performance & Scalability](#performance--scalability)
9. [Disaster Recovery & Business Continuity](#disaster-recovery--business-continuity)
10. [Technology Stack](#technology-stack)
11. [Deployment Architecture](#deployment-architecture)

---

## Executive Summary

### Purpose
This document describes the technical architecture of the AppDynamics License Management System, a comprehensive solution for tracking license consumption, calculating costs, and performing automated chargebacks across PepsiCo business units.

### Key Objectives
- **Automate license tracking**: Replace manual spreadsheet processes with automated data collection
- **Enable cost transparency**: Provide department-level visibility into license costs
- **Support chargeback**: Facilitate accurate financial allocation to business sectors
- **Predictive analytics**: Forecast future license consumption and costs
- **Audit compliance**: Maintain complete data lineage and change history

### Design Principles
1. **Modularity**: Loosely coupled components for easy maintenance and extension
2. **Scalability**: Designed to handle growth in applications and data volume
3. **Reliability**: Automated error handling, retry logic, and health monitoring
4. **Security**: Secrets management, role-based access, audit logging
5. **Performance**: Pre-aggregated data, materialized views, optimized queries
6. **Extensibility**: Plugin architecture supports tool migration and expansion

---

## System Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐              ┌──────────────────┐        │
│  │  AppDynamics     │              │  ServiceNow      │        │
│  │  SaaS Platform   │              │  CMDB            │        │
│  │                  │              │                  │        │
│  │  • License Usage │              │  • Applications  │        │
│  │  • Applications  │              │  • Servers       │        │
│  │  • Tier Metadata │              │  • Relationships │        │
│  └────────┬─────────┘              └────────┬─────────┘        │
│           │                                  │                  │
│           │ OAuth2 API                       │ REST API         │
└───────────┼──────────────────────────────────┼──────────────────┘
            │                                  │
            │                                  │
┌───────────▼──────────────────────────────────▼──────────────────┐
│                    ETL PROCESSING LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Docker Container: ETL Engine                  │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐ │ │
│  │  │ ServiceNow   │  │ AppDynamics  │  │ Reconciliation  │ │ │
│  │  │ Extractor    │  │ Extractor    │  │ Engine          │ │ │
│  │  │              │  │              │  │                 │ │ │
│  │  │ • CMDB Data  │  │ • Usage Data │  │ • Fuzzy Match   │ │ │
│  │  │ • Servers    │  │ • Costs      │  │ • Auto-Link     │ │ │
│  │  │ • Relations  │  │ • Forecasts  │  │ • Manual Queue  │ │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘ │ │
│  │                                                            │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐ │ │
│  │  │ Advanced     │  │ Allocation   │  │ Data Quality    │ │ │
│  │  │ Forecasting  │  │ Engine       │  │ Validator       │ │ │
│  │  │              │  │              │  │                 │ │ │
│  │  │ • ML Models  │  │ • Cost       │  │ • Completeness  │ │ │
│  │  │ • 12-Month   │  │   Distribution│  │ • Accuracy      │ │ │
│  │  │ • Confidence │  │ • Rules      │  │ • Audit Logs    │ │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              │ psycopg2                          │
└──────────────────────────────┼───────────────────────────────────┘
                               │
                               │
┌──────────────────────────────▼───────────────────────────────────┐
│                      DATA WAREHOUSE LAYER                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              PostgreSQL 16 Database                        │ │
│  │                                                            │ │
│  │  ┌──────────────────┐      ┌──────────────────┐          │ │
│  │  │  Dimension       │      │  Fact Tables     │          │ │
│  │  │  Tables          │      │                  │          │ │
│  │  │                  │      │  • Usage         │          │ │
│  │  │  • Applications  │      │  • Costs         │          │ │
│  │  │  • Owners        │      │  • Forecasts     │          │ │
│  │  │  • Sectors       │      │  • Chargebacks   │          │ │
│  │  │  • Capabilities  │      │                  │          │ │
│  │  └──────────────────┘      └──────────────────┘          │ │
│  │                                                            │ │
│  │  ┌──────────────────┐      ┌──────────────────┐          │ │
│  │  │  Configuration   │      │  Audit Tables    │          │ │
│  │  │  Tables          │      │                  │          │ │
│  │  │                  │      │  • ETL Log       │          │ │
│  │  │  • Pricing       │      │  • Lineage       │          │ │
│  │  │  • Rules         │      │  • Reconciliation│          │ │
│  │  │  • Mappings      │      │  • User Actions  │          │ │
│  │  └──────────────────┘      └──────────────────┘          │ │
│  │                                                            │ │
│  │  ┌────────────────────────────────────────────┐          │ │
│  │  │         Materialized Views                 │          │ │
│  │  │  • Monthly Cost Summary                    │          │ │
│  │  │  • Application Cost Current                │          │ │
│  │  └────────────────────────────────────────────┘          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              │ SQL Queries                       │
└──────────────────────────────┼───────────────────────────────────┘
                               │
                               │
┌──────────────────────────────▼───────────────────────────────────┐
│                    VISUALIZATION LAYER                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  Grafana Cloud / Enterprise                │ │
│  │                                                            │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐ │ │
│  │  │ Tab 1:       │  │ Tab 2:       │  │ Tab 3:          │ │ │
│  │  │ Executive    │  │ Usage by     │  │ Cost Analytics  │ │ │
│  │  │ Overview     │  │ License Type │  │                 │ │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘ │ │
│  │                                                            │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐ │ │
│  │  │ Tab 4:       │  │ Tab 5:       │  │ Tab 6:          │ │ │
│  │  │ Peak vs Pro  │  │ Architecture │  │ Trends &        │ │ │
│  │  │ Analysis     │  │ Efficiency   │  │ Forecasts       │ │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘ │ │
│  │                                                            │ │
│  │  ┌──────────────┐  ┌──────────────┐                      │ │
│  │  │ Tab 7:       │  │ Tab 8:       │                      │ │
│  │  │ Chargeback & │  │ Admin Panel  │                      │ │
│  │  │ Allocation   │  │              │                      │ │
│  │  └──────────────┘  └──────────────┘                      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              │ HTTPS / SSO                       │
└──────────────────────────────┼───────────────────────────────────┘
                               │
                               ▼
                         ┌─────────────┐
                         │  End Users  │
                         │  • Viewers  │
                         │  • Admins   │
                         └─────────────┘
```

---

## Infrastructure Components

### Containerization: Docker

**Why Docker:**
- Consistent execution environment across dev/test/prod
- Easy dependency management
- Simplified deployment and scaling
- Isolation of ETL processes

**Container Architecture:**
```yaml
Services:
  postgres:        # Data warehouse
  grafana:         # Visualization platform
  etl:             # Unified ETL orchestrator
  etl_snow:        # ServiceNow-only extraction
  etl_appd:        # AppDynamics-only extraction
```

**Volume Management:**
- `postgres_data`: Persistent database storage
- `grafana_data`: Dashboard configurations
- `etl_logs`: ETL execution logs
- Read-only mounts for scripts and SQL

---

### Database: PostgreSQL 16

**Selection Rationale:**
- **Mature relational model**: Strong ACID compliance, complex joins
- **JSON support**: JSONB for audit logs and flexible metadata
- **Performance**: Excellent query optimization, materialized views
- **Open source**: No licensing costs, active community
- **Enterprise features**: Replication, partitioning, full-text search

**Database Configuration:**
```
Database Name: appd_licensing
Port: 5432
Character Set: UTF-8
Timezone: UTC
Max Connections: 100
Shared Buffers: 256MB (configurable based on host resources)
Work Mem: 4MB
```

**Maintenance Jobs:**
- VACUUM: Weekly automated cleanup
- ANALYZE: Daily statistics update
- Materialized View Refresh: After each ETL run
- Backup: Daily incremental, weekly full

---

### Visualization: Grafana Cloud / Enterprise

**Selection Rationale:**
- **PostgreSQL native support**: Direct SQL queries without ETL
- **Rich visualization**: 40+ panel types, customizable dashboards
- **SSO integration**: SAML/OAuth2 for PepsiCo identity provider
- **Role-based access**: Viewer, Editor, Admin roles
- **Alerting**: Built-in alerting and notification system
- **Cloud-hosted**: No infrastructure maintenance burden

**Dashboard Organization:**
- 8 tabs per SOW requirements
- Dynamic filters (time range, sector, application)
- Drill-through navigation between tabs
- Exportable to PDF for monthly reports

---

### Secrets Management: AWS Systems Manager Parameter Store

**Selection Rationale:**
- **AWS-native**: Integrated with existing PepsiCo AWS infrastructure
- **Secure**: Encryption at rest and in transit
- **Versioned**: Parameter history tracking
- **IAM-controlled**: Fine-grained access control
- **No additional infrastructure**: No Vault deployment needed

**Parameter Structure:**
```
/pepsico/appd-licensing/
  ├── DB_NAME
  ├── DB_USER
  ├── DB_PASSWORD
  ├── APPD_CONTROLLER
  ├── APPD_CLIENT_ID
  ├── APPD_CLIENT_SECRET
  ├── SN_INSTANCE
  ├── SN_USER
  └── SN_PASS
```

**Access Pattern:**
- ETL container retrieves secrets at startup via AWS CLI
- IAM role attached to ECS task (production) or EC2 instance
- Local fallback to `.env` file for development

---

## Data Architecture

### Star Schema Design

**Why Star Schema:**
- **Optimized for analytics**: Fast aggregation queries
- **Business-friendly**: Intuitive dimension/fact separation
- **Scalable**: Handles millions of fact records efficiently
- **Grafana-compatible**: Direct SQL queries without complex joins

**Schema Structure:**

```
Fact Tables (Event Data):
  • license_usage_fact      → Daily usage metrics
  • license_cost_fact       → Calculated costs
  • chargeback_fact         → Monthly aggregated charges
  • forecast_fact           → 12-month projections

Dimension Tables (Reference Data):
  • applications_dim        → Application registry (AppD + ServiceNow)
  • owners_dim              → Ownership hierarchy
  • sectors_dim             → Business sectors
  • capabilities_dim        → License types (APM, RUM, etc.)
  • architecture_dim        → Architecture patterns
  • time_dim                → Time hierarchy
  • servers_dim             → Server CIs
  • app_server_mapping      → App-to-server relationships

Configuration Tables:
  • price_config            → Contract pricing rules
  • allocation_rules        → Shared service cost distribution
  • mapping_overrides       → Manual reconciliation overrides
  • forecast_models         → Algorithm configurations

Audit Tables:
  • etl_execution_log       → Job history
  • data_lineage            → Complete audit trail
  • reconciliation_log      → Matching history
  • user_actions            → Administrative changes
```

**Indexing Strategy:**
- Primary keys: SERIAL (auto-increment surrogate keys)
- Foreign keys: Standard B-tree indexes
- Composite indexes: For frequent join patterns (ts + app_id + capability_id)
- Unique constraints: Enforce data integrity (sn_sys_id, appd_application_id)

---

### Data Model Diagram

```
┌─────────────────────┐
│  applications_dim   │
│  ─────────────────  │
│  PK: app_id         │◄───────┐
│  UK: appd_app_id    │        │
│  UK: sn_sys_id      │        │
│  FK: owner_id       │        │
│  FK: sector_id      │        │
│  FK: architecture_id│        │
└──────────┬──────────┘        │
           │                   │
           │                   │
┌──────────▼──────────┐        │
│ license_usage_fact  │        │
│ ─────────────────── │        │
│ PK: usage_id        │        │
│ FK: app_id          │────────┘
│ FK: capability_id   │
│ ts (timestamp)      │
│ tier (PEAK/PRO)     │
│ units_consumed      │
└──────────┬──────────┘
           │
           │ JOIN (usage × pricing)
           │
┌──────────▼──────────┐
│ license_cost_fact   │
│ ─────────────────── │
│ PK: cost_id         │
│ FK: app_id          │
│ FK: capability_id   │
│ FK: price_id        │
│ ts (timestamp)      │
│ usd_cost $$$$       │◄────┐
└──────────┬──────────┘     │
           │                │
           │ AGGREGATE      │
           │ by month       │
           │                │
┌──────────▼──────────┐     │
│  chargeback_fact    │     │
│  ─────────────────  │     │
│  PK: chargeback_id  │     │
│  FK: app_id         │     │
│  FK: sector_id      │     │
│  month_start (date) │     │
│  usd_amount $$$$    │     │
└─────────────────────┘     │
                            │
┌───────────────────────────┘
│
│  ┌─────────────────┐
│  │  price_config   │
└─►│  ─────────────  │
   │  PK: price_id   │
   │  FK: capability │
   │  tier           │
   │  unit_rate $    │
   │  start_date     │
   │  end_date       │
   └─────────────────┘
```

---

## ETL Pipeline Design

### Pipeline Orchestration

**Execution Sequence:**
```
1. ServiceNow ETL      → Extract CMDB data (applications, servers, relationships)
2. AppDynamics ETL     → Extract usage data, calculate costs, generate chargebacks
3. Reconciliation      → Fuzzy match AppD ↔ ServiceNow applications
4. Advanced Forecasting → Generate 12-month projections with confidence intervals
5. Allocation Engine   → Distribute shared service costs across sectors
6. Materialized Views  → Refresh dashboard performance views
7. Validation          → Data quality checks and reporting
```

**Orchestration Tool:** `entrypoint.sh` (Bash script)
- Sequential execution with error handling
- Exit on first failure (fail-fast)
- Comprehensive logging
- AWS SSM secret retrieval

**Future: Enterprise Scheduler**
- Airflow DAG for production
- Task dependencies with DAG structure
- SLA monitoring and alerting
- Retry logic and backoff strategies

---

### ETL Component Details

#### 1. ServiceNow ETL (`snow_etl.py`)

**Purpose:** Extract CMDB configuration items and relationships

**Data Sources:**
- `cmdb_ci_service`: Business applications
- `cmdb_ci_server`: Server configuration items
- `cmdb_rel_ci`: Application-to-server relationships

**Process Flow:**
```python
1. Authenticate to ServiceNow REST API (Basic Auth)
2. Query cmdb_ci_service with filters:
   - install_status = 1 (Installed)
   - operational_status = 1 (Operational)
3. Extract fields:
   - sys_id, name, owned_by, sector, architecture, h_code
4. Upsert to applications_dim:
   - ON CONFLICT (sn_sys_id) DO UPDATE
5. Query cmdb_ci_server for server CIs
6. Upsert to servers_dim
7. Query cmdb_rel_ci for "Runs on" relationships
8. Populate app_server_mapping
```

**Key Features:**
- Pagination support (1000 records per page)
- Retry logic with exponential backoff
- Field mapping with fallback defaults
- Dimension table upserts (owners, sectors, architecture)

**Output:**
- 40-100 applications loaded
- 50-200 servers loaded
- 10-50 relationships mapped

---

#### 2. AppDynamics ETL (`appd_etl.py`)

**Purpose:** Extract license usage, calculate costs, generate chargebacks

**Data Sources:**
- AppDynamics REST API (future OAuth2 integration)
- Currently: Mock data generator for development

**Process Flow:**
```python
1. Authenticate to AppDynamics (OAuth2)
2. Get list of monitored applications
3. For each application:
   a. Query license usage metrics (daily granularity)
   b. Extract Peak vs. Pro tier metadata
   c. Extract node counts
4. Insert into license_usage_fact
5. Calculate costs:
   JOIN usage × price_config → license_cost_fact
6. Generate chargebacks:
   AGGREGATE costs by month/app/sector → chargeback_fact
7. Generate simple forecasts (replaced by advanced_forecasting.py)
```

**Mock Data Generator:**
- 6 applications
- 91 days of historical data (July 30 - Oct 28, 2025)
- 2 capabilities (APM, MRUM)
- 2 tiers (PEAK, PRO) with random distribution
- Random usage (50-500 units/day)
- Random node counts (5-50 nodes)

**Cost Calculation Formula:**
```sql
usd_cost = ROUND((units_consumed × unit_rate)::numeric, 2)
```

**Output:**
- 1,092 usage records (6 apps × 91 days × 2 capabilities)
- 1,092 cost records (100% coverage)
- 24 chargeback records (6 apps × 4 months)

---

#### 3. Reconciliation Engine (`reconciliation_engine.py`)

**Purpose:** Match AppDynamics applications with ServiceNow CMDB records

**Algorithm:** Fuzzy String Matching (SequenceMatcher - Levenshtein-like)

**Process Flow:**
```python
1. Get unmatched AppD applications:
   WHERE appd_application_name IS NOT NULL AND sn_sys_id IS NULL
2. Get unmatched ServiceNow services:
   WHERE sn_service_name IS NOT NULL AND appd_application_id IS NULL
3. For each AppD app:
   a. Calculate similarity score with all SNOW services
   b. Find best match (highest score)
   c. If score ≥ 80%: Auto-match
      - Update AppD record with ServiceNow metadata
      - Delete orphaned ServiceNow record
      - Log to reconciliation_log (status='auto_matched')
   d. If score 50-79%: Manual review queue
      - Log to reconciliation_log (status='needs_review')
4. Generate reconciliation report:
   - Overall match rate
   - AppD match rate (key metric)
   - Breakdown by status
```

**Match Quality Metrics:**
- Confidence Score: 0-100% (based on string similarity)
- Auto-Match Threshold: ≥80%
- Manual Review Threshold: 50-79%
- No Match: <50%

**Current Performance:**
- 6/6 AppD apps matched (100%)
- All matches at 100% confidence (exact name matches in mock data)

---

#### 4. Advanced Forecasting Engine (`advanced_forecasting.py`)

**Purpose:** Generate 12-month license consumption and cost projections

**Algorithms Implemented:**

**A. Linear Regression**
```python
# scipy.stats.linregress
# Projects trend line forward based on 90-day history
y = mx + b
confidence_interval = 1.96 × standard_error
```

**B. Exponential Smoothing**
```python
# Holt-Winters style smoothing
smoothed[t] = α × actual[t] + (1-α) × smoothed[t-1]
alpha = 0.3 (configurable)
```

**C. Ensemble Method** (Currently Active)
```python
# Weighted average for improved accuracy
forecast = 0.6 × linear_projection + 0.4 × exponential_projection
```

**Process Flow:**
```python
1. Query usage history (90 days minimum)
2. Group by app_id + capability_id + tier
3. For each group:
   a. Extract daily usage values
   b. Check for sufficient data points (≥30 days)
   c. Run ensemble forecast (12 months)
   d. Calculate 95% confidence intervals
   e. Get current pricing rate
   f. Calculate projected costs
   g. Insert into forecast_fact
4. Validate accuracy:
   - Compare last month's forecast vs. actual
   - Calculate MAPE (Mean Absolute Percentage Error)
```

**Output:**
- 288 forecast records (6 apps × 2 capabilities × 2 tiers × 12 months)
- Confidence intervals for risk assessment
- Method tracking for audit trail

---

#### 5. Allocation Engine (`allocation_engine.py`)

**Purpose:** Distribute shared service costs across business sectors

**Allocation Methods:**

**A. Proportional Usage**
```
Sector Allocation = (Sector Usage / Total Usage) × Shared Service Cost
```

**B. Equal Split**
```
Sector Allocation = Shared Service Cost / Number of Active Sectors
```

**C. Custom Formula** (40% usage, 60% equal)
```
Sector Allocation = 0.4 × Proportional + 0.6 × Equal
```

**Process Flow:**
```python
1. Seed default allocation rules (if not exist)
2. Identify shared services:
   - H-code patterns: PLATFORM, SHARED, GLOBAL
   - Sector name: "Corporate/Shared Services", "Global IT"
3. For each shared service:
   a. Get total monthly cost
   b. Match to allocation rule (by H-code pattern)
   c. Calculate sector allocations
   d. Insert into chargeback_fact:
      chargeback_cycle = 'allocated_shared_service'
4. Generate allocation summary report
```

**Current Status:**
- 0 shared services identified (mock data has no shared services)
- Ready for production data with proper H-codes

---

#### 6. Data Quality Validation (`validate_pipeline.py`)

**Purpose:** Comprehensive data quality checks after each ETL run

**Validation Checks:**

1. **Table Row Counts**
   - Verify all tables populated
   - Detect empty tables (potential ETL failure)

2. **Reconciliation Match Rate**
   - AppD match rate (target: 100%)
   - Overall match rate (target: >95%)

3. **Data Freshness**
   - Last successful ETL run timestamp
   - Detect stale data (>24 hours old)

4. **Orphaned Records**
   - Usage records without costs
   - Costs without usage
   - Detect foreign key integrity issues

5. **Forecast Coverage**
   - % of apps with forecasts
   - Minimum 12-month projection

6. **Cost Calculation Accuracy**
   - Expected cost vs. actual cost variance
   - Target: ≤2% (currently 0.00-0.46%)

**Output:**
- Comprehensive validation report
- Pass/fail status for each check
- Recommendations for issues found

---

## Integration Architecture

### AppDynamics Integration

**API Endpoint:** `https://{controller}.saas.appdynamics.com`

**Authentication:** OAuth2 (Client Credentials Flow)
```
POST /controller/api/oauth/access_token
Body: {
  "client_id": "api_client@account",
  "client_secret": "secret",
  "grant_type": "client_credentials"
}
Response: {
  "access_token": "...",
  "expires_in": 3600
}
```

**Key API Endpoints:**
- `/controller/rest/applications` - List monitored applications
- `/controller/rest/licenseusage/account/{id}` - License consumption metrics
- `/controller/restui/application/{appId}/metric-data` - Detailed metrics

**Data Extraction Pattern:**
- Incremental loads (last 24 hours)
- Full historical backfill (initial load)
- Rate limiting: 100 req/min
- Retry logic: Exponential backoff (2^n seconds)

**Current Status:** Mock data generator (OAuth2 client ready for credentials)

---

### ServiceNow Integration

**API Endpoint:** `https://{instance}.service-now.com/api/now/table`

**Authentication:** Basic Auth (API user credentials)

**Key API Endpoints:**
- `/api/now/table/cmdb_ci_service` - Business applications
- `/api/now/table/cmdb_ci_server` - Server CIs
- `/api/now/table/cmdb_rel_ci` - CI relationships

**Query Filters:**
```
cmdb_ci_service:
  install_status = 1 (Installed)
  operational_status = 1 (Operational)

cmdb_ci_server:
  operational_status = 1 (Operational)

cmdb_rel_ci:
  type.name = "Runs on::Runs"
```

**Pagination:**
- Limit: 1000 records per request
- Offset-based pagination
- Total record count in response headers

**Field Mapping:**
```
ServiceNow Field          → Database Column
─────────────────────────────────────────────
sys_id                    → sn_sys_id
name                      → sn_service_name
owned_by.display_value    → owner_name (via owners_dim)
u_sector.display_value    → sector_name (via sectors_dim)
u_architecture_type       → pattern_name (via architecture_dim)
u_h_code / cost_center    → h_code
support_group             → support_group
```

**Current Status:** Production-ready (tested with dev instance)

---

## Security Architecture

### Authentication & Authorization

**AWS SSM Parameter Store:**
- Secrets encrypted at rest (AWS KMS)
- IAM role-based access control
- Parameter versioning and audit logging
- Least-privilege principle

**Grafana SSO (Future):**
- SAML 2.0 or OAuth2 integration
- PepsiCo identity provider
- Role mapping: AD groups → Grafana roles

**Database Access:**
- PostgreSQL user: `etl_analytics` (read-write access to appd_licensing schema)
- Password rotation: 90 days (recommended)
- Connection limit: 100 concurrent connections
- SSL/TLS encryption (production)

---

### Network Security

**Container Networking:**
- Private Docker network (`pepsico-network`)
- No direct external access to PostgreSQL
- Grafana exposed via reverse proxy (production)

**Firewall Rules (Production):**
- Allow: ETL container → PostgreSQL (5432)
- Allow: ETL container → AppDynamics API (443)
- Allow: ETL container → ServiceNow API (443)
- Allow: Grafana → PostgreSQL (5432)
- Allow: Users → Grafana (443)
- Deny: All other traffic

**API Security:**
- TLS 1.2+ for all external communications
- OAuth2 tokens cached and refreshed automatically
- API credentials never logged or exposed
- Request/response bodies sanitized in logs

---

### Audit & Compliance

**Complete Audit Trail:**
- ETL execution history (`etl_execution_log`)
- Data lineage tracking (`data_lineage`)
- User administrative actions (`user_actions`)
- Reconciliation decisions (`reconciliation_log`)

**Data Retention:**
- Operational data: 24 months online
- Historical data: 7 years (archive to S3 recommended)
- Audit logs: 7 years (compliance requirement)

**Compliance Features:**
- SOX compliance: Complete data lineage
- Change tracking: All updates logged with before/after values
- Access logs: User actions timestamped and attributed
- Data integrity: Foreign key constraints, check constraints

---

## Performance & Scalability

### Current Performance Metrics

**ETL Execution Time:**
- ServiceNow ETL: ~10 seconds (40 apps, 40 servers)
- AppDynamics ETL: ~5 seconds (mock data)
- Reconciliation: ~2 seconds (6 apps)
- Forecasting: ~3 seconds (24 forecasts)
- Allocation: ~1 second (0 shared services)
- Total Pipeline: ~25 seconds

**Dashboard Query Performance:**
- Target: <5 seconds per panel
- Current: Not yet measured (dashboards in development)
- Optimization: Materialized views for complex aggregations

**Database Size:**
- Current: ~50 MB (6 apps, 91 days of data)
- Projected 1 year: ~2 GB (100 apps, 365 days)
- Projected 3 years: ~6 GB (with archival strategy)

---

### Scalability Considerations

**Horizontal Scaling:**
- ETL containers: Can run multiple instances with different app subsets
- Database: PostgreSQL read replicas for dashboard queries
- Grafana: Cloud-hosted, auto-scaling

**Vertical Scaling:**
- Database: Increase shared_buffers, work_mem for larger datasets
- ETL: Increase container CPU/memory limits

**Data Volume Projections:**

| Metric | Year 1 | Year 3 | Year 5 |
|--------|--------|--------|--------|
| Applications | 100 | 200 | 300 |
| Daily Usage Records | 200 | 400 | 600 |
| Annual Fact Records | 73K | 146K | 219K |
| Database Size | 2 GB | 6 GB | 10 GB |
| ETL Duration | 60s | 90s | 120s |

**Optimization Strategies:**
1. **Partitioning**: Partition license_usage_fact by month (when >1M rows)
2. **Archival**: Move >2-year-old data to S3/Glacier
3. **Materialized Views**: Pre-aggregate common queries
4. **Connection Pooling**: PgBouncer for dashboard connections
5. **Caching**: Redis for frequently accessed dimension data (future)

---

### Materialized Views

**Purpose:** Pre-compute expensive aggregations for dashboard performance

**mv_monthly_cost_summary:**
```sql
-- Aggregates daily costs to monthly summary
-- Reduces dashboard query time from 3s to <500ms
SELECT 
    DATE_TRUNC('month', ts) as month_start,
    app_id, capability_id, tier,
    SUM(usd_cost) as total_cost,
    AVG(usd_cost) as avg_daily_cost,
    COUNT(*) as days_active
FROM license_cost_fact
GROUP BY 1,2,3,4;

-- Refresh: After each ETL run
-- Index: (month_start, app_id, capability_id, tier)
```

**mv_app_cost_current:**
```sql
-- Current month application costs with metadata
-- Used by executive dashboard and cost analytics
SELECT 
    ad.app_id,
    COALESCE(ad.appd_application_name, ad.sn_service_name) as app_name,
    o.owner_name, s.sector_name, ar.pattern_name,
    SUM(lcf.usd_cost) as month_cost,
    COUNT(DISTINCT lcf.capability_id) as capability_count
FROM applications_dim ad
LEFT JOIN license_cost_fact lcf ON lcf.app_id = ad.app_id
    AND DATE_TRUNC('month', lcf.ts) = DATE_TRUNC('month', NOW())
-- ... joins to dimension tables
GROUP BY ad.app_id, ...;

-- Refresh: After each ETL run
-- Index: (app_id, sector_name)
```

**Refresh Strategy:**
- Triggered automatically by entrypoint.sh after Step 5 (Allocation)
- Uses `REFRESH MATERIALIZED VIEW CONCURRENTLY` (no table locks)
- Requires unique index for concurrent refresh
- Estimated refresh time: 1-2 seconds

---

## Disaster Recovery & Business Continuity

### Backup Strategy

**PostgreSQL Backups:**
- **Frequency**: Daily automated backups
- **Method**: `pg_dump` full database dump
- **Retention**: 30 days online, 1 year archive
- **Storage**: AWS S3 with versioning enabled
- **Encryption**: AES-256 at rest

**Backup Command:**
```bash
pg_dump -U etl_analytics -h postgres -d appd_licensing \
  --format=custom --compress=9 \
  --file=/backup/appd_licensing_$(date +%Y%m%d).dump
```

**Recovery Time Objective (RTO):** 4 hours  
**Recovery Point Objective (RPO):** 24 hours (daily ETL)

---

### High Availability (Production)

**PostgreSQL HA:**
- **Primary-Replica Setup**: Streaming replication
- **Failover**: Automatic with Patroni or manual
- **Read Replicas**: 1-2 replicas for dashboard queries
- **Connection Pooling**: PgBouncer for connection management

**ETL Resilience:**
- **Retry Logic**: Exponential backoff on API failures
- **Idempotency**: Re-running ETL produces same results
- **Error Handling**: Graceful degradation (continue on non-critical failures)
- **Monitoring**: ETL execution log tracks all runs

**Grafana Availability:**
- **Cloud-hosted**: 99.9% SLA from Grafana Cloud
- **Dashboard Backup**: JSON exports stored in Git repository
- **User Management**: SSO integration prevents lockout

---

### Monitoring & Alerting

**ETL Monitoring:**
- Daily ETL success/failure notifications
- Data quality check failures
- Match rate below 95% threshold
- Cost calculation variance >2%

**Database Monitoring:**
- Disk space utilization (alert at 80%)
- Connection count (alert at 90% of max)
- Query performance (slow query log >5 seconds)
- Replication lag (alert at >5 minutes)

**Alerting Channels:**
- Email: ETL team distribution list
- Slack: #appd-licensing-alerts channel (future)
- PagerDuty: Critical failures only (production)

---

## Technology Stack

### Core Technologies

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Database** | PostgreSQL | 16 | Data warehouse |
| **ETL Language** | Python | 3.12 | Data processing |
| **Containerization** | Docker | 24+ | Deployment |
| **Orchestration** | Docker Compose | 2.x | Local dev orchestration |
| **Visualization** | Grafana | Enterprise/Cloud | Dashboards |
| **Secrets** | AWS SSM | N/A | Credential management |

### Python Libraries

| Library | Version | Purpose |
|---------|---------|---------|
| `psycopg2` | 2.9+ | PostgreSQL driver |
| `requests` | 2.31+ | HTTP API calls |
| `boto3` | 1.34+ | AWS SDK (SSM) |
| `scipy` | 1.11+ | Statistical forecasting |
| `numpy` | 1.26+ | Numerical computations |

### Database Extensions

| Extension | Purpose |
|-----------|---------|
| `pg_stat_statements` | Query performance monitoring |
| `pgcrypto` | Encryption functions (if needed) |

---

## Deployment Architecture

### Development Environment

**Host:** Developer workstation (macOS/Windows/Linux)  
**Orchestration:** Docker Desktop + docker-compose  
**Database:** Single PostgreSQL container  
**Grafana:** Local Grafana OSS container (port 3000)  
**ETL:** Manual execution via `docker-compose run --rm etl`

**Network:**
```
pepsico-network (bridge)
  ├── pepsico-postgres (postgres:16)
  ├── pepsico-grafana (grafana/grafana:12.2.1)
  └── pepsico-etl-unified (custom Python 3.12 image)
```

**Volumes:**
```
postgres_data → /var/lib/postgresql/data
grafana_data → /var/lib/grafana
etl_logs → /var/log/etl
```

---

### Production Environment (Recommended)

**Hosting:** AWS ECS (Elastic Container Service) or EC2

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐       ┌─────────────────────┐     │
│  │   Public Subnet     │       │   Private Subnet    │     │
│  │                     │       │                     │     │
│  │  ┌──────────────┐  │       │  ┌──────────────┐  │     │
│  │  │ Application  │  │       │  │ RDS          │  │     │
│  │  │ Load         │  │       │  │ PostgreSQL   │  │     │
│  │  │ Balancer     │  │       │  │ Primary      │  │     │
│  │  └──────┬───────┘  │       │  └──────┬───────┘  │     │
│  │         │          │       │         │          │     │
│  └─────────┼──────────┘       │  ┌──────▼───────┐  │     │
│            │                  │  │ RDS          │  │     │
│  ┌─────────▼──────────┐       │  │ PostgreSQL   │  │     │
│  │   Private Subnet    │       │  │ Replica      │  │     │
│  │                     │       │  └──────────────┘  │     │
│  │  ┌──────────────┐  │       │                     │     │
│  │  │ ECS Fargate  │  │       └─────────────────────┘     │
│  │  │ ETL Task     │◄─┼───────────────┐                   │
│  │  └──────────────┘  │               │                   │
│  │                     │               │                   │
│  │  ┌──────────────┐  │         ┌─────▼───────┐          │
│  │  │ EventBridge  │  │         │ AWS Systems │          │
│  │  │ Scheduler    │  │         │ Manager     │          │
│  │  │ (Daily 2AM)  │  │         │ Parameters  │          │
│  │  └──────────────┘  │         └─────────────┘          │
│  └─────────────────────┘                                  │
└─────────────────────────────────────────────────────────────┘
           │
           │ HTTPS
           ▼
    ┌────────────────┐
    │ Grafana Cloud  │
    │ (External SaaS)│
    └────────────────┘
```

**Components:**

1. **RDS PostgreSQL Multi-AZ:**
   - Instance Type: db.r6g.xlarge (4 vCPU, 32 GB RAM)
   - Storage: 100 GB gp3 (expandable to 1 TB)
   - Automated Backups: 30 days retention
   - Read Replica: For dashboard queries

2. **ECS Fargate (ETL):**
   - Task Definition: 2 vCPU, 4 GB RAM
   - Schedule: EventBridge rule (cron: 0 2 * * ? *)
   - IAM Role: Access to SSM parameters, RDS
   - Logs: CloudWatch Logs (30-day retention)

3. **Grafana Cloud:**
   - Hosted service (no infrastructure)
   - Connection to RDS via VPC peering or public endpoint (with IP whitelist)
   - SSO integration with PepsiCo IdP

4. **Secrets Management:**
   - AWS Systems Manager Parameter Store
   - Parameters encrypted with KMS
   - IAM policies restrict access to ETL task role

---

### Deployment Process

**Development to Production:**

1. **Code Changes:**
   ```bash
   # Local development and testing
   git checkout -b feature/new-feature
   # Make changes, test locally
   docker-compose down -v && docker-compose up -d
   docker-compose run --rm etl
   # Commit and push
   git push origin feature/new-feature
   ```

2. **CI/CD Pipeline (Future):**
   ```yaml
   # .github/workflows/deploy.yml or similar
   - Build Docker image
   - Push to Amazon ECR
   - Update ECS task definition
   - Deploy to production (blue-green)
   ```

3. **Manual Deployment (Current):**
   ```bash
   # Build and tag image
   docker build -t appd-etl:v1.0 -f docker/etl/Dockerfile .
   
   # Push to ECR
   aws ecr get-login-password | docker login --username AWS --password-stdin
   docker tag appd-etl:v1.0 123456789012.dkr.ecr.us-east-1.amazonaws.com/appd-etl:v1.0
   docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/appd-etl:v1.0
   
   # Update ECS task definition
   aws ecs register-task-definition --cli-input-json file://task-def.json
   
   # Update service (triggers deployment)
   aws ecs update-service --cluster appd-cluster --service etl-service --force-new-deployment
   ```

---

## Extensibility & Future Enhancements

### Plugin Architecture

**Design Principle:** Tool-agnostic core with pluggable data sources

**Current Implementation:**
- ETL scripts isolated by source system (snow_etl.py, appd_etl.py)
- Shared utilities (audit_logger.py)
- Standard database schema (not tool-specific)

**Future Tool Migration:**
- **Scenario:** Replace AppDynamics with Dynatrace
- **Approach:**
  1. Create new `dynatrace_etl.py` following same interface
  2. Map Dynatrace metrics to existing `license_usage_fact` schema
  3. Update `entrypoint.sh` to call new script
  4. No changes to downstream (cost calc, forecasting, dashboards)

**Interface Contract:**
```python
# Standard ETL interface for any monitoring tool
def extract_applications() -> List[Application]:
    """Return list of monitored applications"""
    pass

def extract_usage_metrics(app_id, start_date, end_date) -> List[UsageMetric]:
    """Return usage metrics for date range"""
    pass

def get_tier_metadata(app_id) -> str:
    """Return license tier (PEAK/PRO or equivalent)"""
    pass
```

---

### Planned Enhancements

**Phase 2 Features:**
1. **REST API Layer:**
   - FastAPI or Flask application
   - Endpoints: /applications, /costs, /forecasts, /chargebacks
   - Authentication: JWT tokens
   - Rate limiting: 1000 req/hour per user

2. **Advanced Alerting:**
   - Budget threshold alerts
   - Anomaly detection (sudden usage spikes)
   - License exhaustion predictions
   - Automated email notifications

3. **Self-Service Portal:**
   - Manual mapping UI (Streamlit or React)
   - Price configuration management
   - Allocation rule builder
   - Report scheduling

4. **ML Model Improvements:**
   - ARIMA/SARIMA for seasonal forecasting
   - Prophet for holiday effects
   - Ensemble model comparison (A/B testing)
   - Automated model selection

5. **Data Quality Framework:**
   - Great Expectations integration
   - Automated data profiling
   - Drift detection
   - Quality score dashboard

---

## Appendix: Configuration Files

### docker-compose.yaml (Simplified)

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: appd_licensing
      POSTGRES_USER: etl_analytics
      POSTGRES_PASSWORD: appd_pass
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./sql/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "etl_analytics"]
      interval: 5s
      timeout: 5s
      retries: 5

  grafana:
    image: grafana/grafana:12.2.1
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      postgres:
        condition: service_healthy

  etl:
    build:
      context: .
      dockerfile: docker/etl/Dockerfile
    command: ["./entrypoint.sh"]
    environment:
      - DB_HOST=postgres
      - SSM_PATH=/pepsico/appd-licensing
    volumes:
      - ./scripts:/app/scripts:ro
      - ./sql:/app/sql:ro
      - etl_logs:/var/log/etl
      - ~/.aws:/root/.aws:ro
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
  grafana_data:
  etl_logs:

networks:
  pepsico-network:
    driver: bridge
```

---

### Dockerfile (ETL Container)

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN pip install awscli

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY sql/init sql/init
COPY scripts/etl scripts/etl
COPY docker/etl/entrypoint.sh .

# Make entrypoint executable
RUN chmod +x entrypoint.sh

# Set environment
ENV PYTHONPATH=/app/scripts
ENV ETL_USER=devuser

CMD ["./entrypoint.sh"]
```

---

### requirements.txt

```
# Database
psycopg2-binary==2.9.9

# HTTP requests
requests==2.31.0

# AWS integration
boto3==1.34.44

# Data science
numpy==1.26.3
scipy==1.11.4

# Utilities
python-dotenv==1.0.0
```

---

## Document Control

**Version History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-30 | CDW Data Engineering | Initial release |

**Approval:**

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Technical Lead | | | |
| PepsiCo IT Sponsor | | | |
| Security Review | | | |

**Distribution:**
- PepsiCo IT Leadership
- Application Development Team
- Operations Team
- Security & Compliance Team

---

**END OF TECHNICAL ARCHITECTURE DOCUMENT**