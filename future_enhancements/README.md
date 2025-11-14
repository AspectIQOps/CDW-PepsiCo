# Future Enhancements

This directory contains features and tools that were implemented but are not part of the MVP delivery scope.

## Scripts

### audit_logger.py
**Purpose:** Comprehensive audit logging framework for tracking user actions, data modifications, and ETL operations.

**Status:** Module exists but not actively used in MVP. The current implementation uses basic ETL execution logging directly to the `etl_execution_log` table, which meets SOW requirements for pipeline health monitoring.

**Future Use Cases:**
- Detailed user action tracking (manual overrides, cost adjustments)
- Data lineage for transformations
- Change audit trail for compliance
- Admin actions history for dashboards

**Integration Notes:**
- Database schema includes audit-related tables
- Admin Panel dashboard has placeholder panels for audit features
- Module is ready to integrate when enhanced audit requirements are needed

---

### populate_demo_data.py
**Purpose:** Generates realistic demonstration data for client presentations and testing.

**Features:**
- Creates 60 demo applications across 3 controllers
- Generates 6 months of historical data
- 85% H-code coverage, 70% CMDB match rate
- Refreshes all materialized views after population

**Usage:**
```bash
# Set up environment
python3 -m venv venv
source venv/bin/activate
pip install psycopg2-binary

# Set credentials from AWS SSM
export DB_HOST=$(aws ssm get-parameter --name /pepsico/DB_HOST --region us-east-2 --query 'Parameter.Value' --output text)
export DB_NAME=$(aws ssm get-parameter --name /pepsico/DB_NAME --region us-east-2 --query 'Parameter.Value' --output text)
export DB_USER=$(aws ssm get-parameter --name /pepsico/DB_USER --region us-east-2 --query 'Parameter.Value' --output text)
export DB_PASSWORD=$(aws ssm get-parameter --name /pepsico/DB_PASSWORD --with-decryption --region us-east-2 --query 'Parameter.Value' --output text)

# Run script
python3 future_enhancements/scripts/populate_demo_data.py
```

**Why Not in MVP:**
- Production system uses real AppDynamics data
- Demo data useful for testing but not required for delivery
- Can be used optionally for screenshots or demonstrations

---

## Potential Future Enhancements

### 1. Concurrent Refresh for Remaining Views
**Current State:** 4 of 8 materialized views use non-concurrent refresh (brief table locks during refresh)

**Views to Enhance:**
- `mv_cost_by_sector_controller` (5.2s)
- `mv_cost_by_owner_controller` (3.5s)
- `mv_architecture_metrics_90d` (128.8s) - **Priority: HIGH**
- `mv_monthly_chargeback_summary` (0.1s)

**Implementation:** Add unique indexes to enable zero-downtime CONCURRENT refresh

---

### 2. Enhanced Forecast Validation
**Current State:** Forecasting generates 10,344 records but validation shows "Insufficient data"

**Enhancement:** Once sufficient historical data accumulates (6+ months), implement:
- Mean Absolute Percentage Error (MAPE) tracking
- Forecast accuracy trending
- Automatic model selection based on validation metrics
- Alert when forecast accuracy degrades

---

### 3. Admin Panel Audit Features
**Current State:** Dashboard panels exist but show "no data"

**Features to Implement:**
- Active Manual Overrides tracking
- Admin Actions history
- Top Active Users monitoring
- Data Lineage visualization
- Data Operations audit trail

**Dependencies:** Requires `audit_logger.py` integration

---

### 4. Real-time Anomaly Detection
**Concept:** Detect unusual cost or usage patterns in real-time

**Potential Features:**
- Cost spike detection
- Usage pattern anomalies
- CMDB drift alerts
- License utilization warnings

---

### 5. Multi-tenant Support
**Current State:** System handles multiple controllers with filtering

**Enhancement:** Full multi-tenant isolation with:
- Customer-specific dashboards
- Row-level security
- Separate data retention policies
- Customer-specific alerting

---

## Notes

These features were partially implemented or designed but are not required for the current Statement of Work. They represent natural extensions of the platform's capabilities and can be prioritized based on customer feedback and future requirements.
