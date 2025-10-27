-- 02_create_tables.sql
-- Creates all Fact, Dimension, Configuration, and Audit tables required by SoW (Section 2.5.3)

-- Drop tables if they exist (Reverse order of creation due to FK dependencies)
DROP TABLE IF EXISTS chargeback_fact;
DROP TABLE IF EXISTS forecast_fact;
DROP TABLE IF EXISTS license_cost_fact;
DROP TABLE IF EXISTS license_usage_fact;
DROP TABLE IF EXISTS data_lineage;
DROP TABLE IF EXISTS reconciliation_log;
DROP TABLE IF EXISTS user_actions;
DROP TABLE IF EXISTS mapping_overrides;
DROP TABLE IF EXISTS allocation_rules;
DROP TABLE IF EXISTS price_config;
DROP TABLE IF EXISTS applications_dim;
DROP TABLE IF EXISTS time_dim;
DROP TABLE IF EXISTS capabilities_dim;
DROP TABLE IF EXISTS architecture_dim;
DROP TABLE IF EXISTS sectors_dim;
DROP TABLE IF EXISTS owners_dim;
DROP TABLE IF EXISTS etl_execution_log;


-- ----------------------------------------------------
-- 1. DIMENSION TABLES (Reordered for dependency resolution)
-- ----------------------------------------------------

-- Owners dimension (Ownership Hierarchy)
CREATE TABLE owners_dim (
    owner_id SERIAL PRIMARY KEY,
    owner_name TEXT NOT NULL, -- Primary owner/manager name
    organizational_hierarchy TEXT, -- e.g., 'PepsiCo/Global IT/Infrastructure'
    email TEXT
);

-- Sectors dimension (Business Sectors)
CREATE TABLE sectors_dim (
    sector_id SERIAL PRIMARY KEY,
    sector_name TEXT UNIQUE NOT NULL -- e.g., 'Beverages North America', 'Frito Lay'
);

-- Architecture dimension (Monolith/Microservices)
CREATE TABLE architecture_dim (
    architecture_id SERIAL PRIMARY KEY,
    pattern_name TEXT UNIQUE NOT NULL, -- e.g., 'Monolith', 'Microservices'
    description TEXT
);

-- Capabilities dimension (License Types: APM, RUM, Synthetic, DB)
CREATE TABLE capabilities_dim (
    capability_id SERIAL PRIMARY KEY,
    capability_code TEXT UNIQUE NOT NULL, -- e.g., 'APM', 'RUM', 'SYNTHETIC'
    description TEXT
);

-- Time dimension (Granularity for reporting, pre-populated)
CREATE TABLE time_dim (
    ts TIMESTAMP PRIMARY KEY,
    year INT NOT NULL,
    month INT NOT NULL,
    day INT NOT NULL,
    yyyy_mm TEXT NOT NULL
);


-- Applications dimension (CMDB & AppD linkage) - REFERENCES are now valid
CREATE TABLE applications_dim (
    app_id SERIAL PRIMARY KEY,
    appd_application_id INT UNIQUE,
    appd_application_name TEXT NOT NULL,
    sn_sys_id TEXT UNIQUE NOT NULL, -- ServiceNow Service CMDB ID (cmdb_ci_service)
    sn_service_name TEXT,
    owner_id INT NOT NULL REFERENCES owners_dim(owner_id), -- FK to owners_dim
    sector_id INT NOT NULL REFERENCES sectors_dim(sector_id), -- FK to sectors_dim
    architecture_id INT NOT NULL REFERENCES architecture_dim(architecture_id), -- FK to architecture_dim
    h_code TEXT, -- Cost Center (PepsiCo responsibility to populate)
    -- Additional metadata from AppD/SNOW
    is_critical BOOLEAN DEFAULT FALSE,
    support_group TEXT,
    -- Audit fields
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);


-- ----------------------------------------------------
-- 2. CONFIGURATION TABLES
-- ----------------------------------------------------

-- Price configuration (Contract-based pricing with renewal periods)
CREATE TABLE price_config (
    price_id SERIAL PRIMARY KEY,
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL, -- 'Peak' or 'Pro'
    start_date DATE NOT NULL,
    end_date DATE,
    unit_rate NUMERIC NOT NULL, -- Cost per unit (e.g., USD per APM Unit)
    contract_renewal_date DATE
);

-- Allocation rules (Shared service cost distribution logic)
CREATE TABLE allocation_rules (
    rule_id SERIAL PRIMARY KEY,
    rule_name TEXT NOT NULL,
    distribution_method TEXT NOT NULL, -- e.g., 'Equal Split', 'Usage Weight'
    shared_service_code TEXT,
    applies_to_sector_id INT REFERENCES sectors_dim(sector_id),
    is_active BOOLEAN DEFAULT TRUE
);

-- Mapping overrides (Manual reconciliation UI for exceptions)
CREATE TABLE mapping_overrides (
    override_id SERIAL PRIMARY KEY,
    source_system TEXT NOT NULL, -- 'AppDynamics' or 'ServiceNow'
    source_key TEXT NOT NULL, -- The unmatched key (e.g., AppD Application Name)
    target_table TEXT NOT NULL, -- The table being updated (e.g., 'applications_dim')
    target_field TEXT NOT NULL, -- The field being overridden (e.g., 'h_code')
    override_value TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT now(),
    updated_by TEXT
);

-- ----------------------------------------------------
-- 3. FACT TABLES
-- ----------------------------------------------------

-- License usage fact (Granular daily usage metrics)
CREATE TABLE license_usage_fact (
    ts TIMESTAMP NOT NULL REFERENCES time_dim(ts),
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL, -- 'Peak' or 'Pro'
    units_consumed NUMERIC NOT NULL,
    nodes_count INT,
    servers_count INT,
    PRIMARY KEY(ts, app_id, capability_id, tier)
);

-- License cost fact (Calculated costs with full attribution)
CREATE TABLE license_cost_fact (
    ts TIMESTAMP NOT NULL REFERENCES time_dim(ts),
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL,
    usd_cost NUMERIC NOT NULL,
    price_id INT REFERENCES price_config(price_id),
    PRIMARY KEY(ts, app_id, capability_id, tier)
);

-- Forecast fact (Prediction data for 12, 18, 24-month projections)
CREATE TABLE forecast_fact (
    month_start DATE NOT NULL,
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL,
    projected_units NUMERIC,
    projected_cost NUMERIC,
    confidence_interval_high NUMERIC,
    confidence_interval_low NUMERIC,
    method TEXT, -- e.g., 'Linear', 'Exponential', 'Seasonal'
    PRIMARY KEY(month_start, app_id, capability_id, tier)
);

-- Chargeback fact (Monthly department charges)
CREATE TABLE chargeback_fact (
    month_start DATE NOT NULL,
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    h_code TEXT, -- The final resolved H-code for charging
    sector_id INT NOT NULL REFERENCES sectors_dim(sector_id),
    owner_id INT NOT NULL REFERENCES owners_dim(owner_id),
    usd_amount NUMERIC NOT NULL,
    chargeback_cycle TEXT, -- e.g., 'Monthly'
    is_finalized BOOLEAN DEFAULT FALSE,
    PRIMARY KEY(month_start, app_id)
);

-- ----------------------------------------------------
-- 4. AUDIT TABLES
-- ----------------------------------------------------

-- ETL execution log (Job history)
CREATE TABLE etl_execution_log (
    run_id SERIAL PRIMARY KEY,
    job_name TEXT NOT NULL, -- e.g., 'appd_full_load', 'snow_incremental'
    started_at TIMESTAMP DEFAULT now(),
    finished_at TIMESTAMP,
    status TEXT, -- 'SUCCESS', 'FAILURE', 'RUNNING'
    rows_ingested INT,
    error_message TEXT
);

-- Data lineage (Full audit trail of data changes)
CREATE TABLE data_lineage (
    lineage_id SERIAL PRIMARY KEY,
    run_id INT REFERENCES etl_execution_log(run_id),
    source_system TEXT,
    source_endpoint TEXT,
    target_table TEXT NOT NULL,
    target_pk JSONB, -- JSON representation of the primary key
    changed_fields JSONB, -- JSON representation of fields that were updated
    action TEXT -- 'INSERT', 'UPDATE', 'DELETE'
);

-- Reconciliation log (Matching history)
CREATE TABLE reconciliation_log (
    reconciliation_id SERIAL PRIMARY KEY,
    match_run_ts TIMESTAMP DEFAULT now(),
    source_a TEXT, -- 'AppDynamics'
    source_b TEXT, -- 'ServiceNow'
    match_key_a TEXT, -- AppD name
    match_key_b TEXT, -- SNOW name
    confidence_score NUMERIC,
    match_status TEXT, -- 'MATCHED', 'FUZZY_MATCH', 'MANUAL_OVERRIDE', 'UNMATCHED'
    resolved_app_id INT REFERENCES applications_dim(app_id)
);

-- User actions (Administrative changes)
CREATE TABLE user_actions (
    action_id SERIAL PRIMARY KEY,
    user_name TEXT NOT NULL,
    action_type TEXT NOT NULL, -- e.g., 'PRICE_UPDATE', 'MAPPING_OVERRIDE'
    target_table TEXT,
    details JSONB,
    action_ts TIMESTAMP DEFAULT now()
);

-- ----------------------------------------------------
-- 5. ACCESS CONTROL
-- We assume the ETL user (devuser) will handle all application data.
-- ----------------------------------------------------

-- Grant full access to the ETL user (devuser) on all new tables and sequences
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_type IN ('BASE TABLE', 'VIEW')
    LOOP
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO devuser;', t.table_name);
    END LOOP;

    -- Grant access to sequences for SERIAL primary keys
    FOR t IN
        SELECT sequence_name
        FROM information_schema.sequences
        WHERE sequence_schema = 'public'
    LOOP
        EXECUTE format('GRANT USAGE, SELECT, UPDATE ON SEQUENCE %I TO devuser;', t.sequence_name);
    END LOOP;
END
$$;
