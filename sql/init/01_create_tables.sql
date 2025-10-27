-- 02_create_tables.sql
-- Creates all Fact, Dimension, Configuration, and Audit tables required by SoW (Section 2.5.3)
-- FIXED: Made FK constraints optional with default values to allow ETL to populate gradually

-- Drop tables if they exist (Reverse order of creation due to FK dependencies)
DROP TABLE IF EXISTS chargeback_fact CASCADE;
DROP TABLE IF EXISTS forecast_fact CASCADE;
DROP TABLE IF EXISTS license_cost_fact CASCADE;
DROP TABLE IF EXISTS license_usage_fact CASCADE;
DROP TABLE IF EXISTS data_lineage CASCADE;
DROP TABLE IF EXISTS reconciliation_log CASCADE;
DROP TABLE IF EXISTS user_actions CASCADE;
DROP TABLE IF EXISTS mapping_overrides CASCADE;
DROP TABLE IF EXISTS allocation_rules CASCADE;
DROP TABLE IF EXISTS price_config CASCADE;
DROP TABLE IF EXISTS applications_dim CASCADE;
DROP TABLE IF EXISTS time_dim CASCADE;
DROP TABLE IF EXISTS capabilities_dim CASCADE;
DROP TABLE IF EXISTS architecture_dim CASCADE;
DROP TABLE IF EXISTS sectors_dim CASCADE;
DROP TABLE IF EXISTS owners_dim CASCADE;
DROP TABLE IF EXISTS etl_execution_log CASCADE;


-- ----------------------------------------------------
-- 1. DIMENSION TABLES (Reordered for dependency resolution)
-- ----------------------------------------------------

-- Owners dimension (Ownership Hierarchy)
CREATE TABLE owners_dim (
    owner_id SERIAL PRIMARY KEY,
    owner_name TEXT NOT NULL,
    organizational_hierarchy TEXT,
    email TEXT
);

-- Sectors dimension (Business Sectors)
CREATE TABLE sectors_dim (
    sector_id SERIAL PRIMARY KEY,
    sector_name TEXT UNIQUE NOT NULL
);

-- Architecture dimension (Monolith/Microservices)
CREATE TABLE architecture_dim (
    architecture_id SERIAL PRIMARY KEY,
    pattern_name TEXT UNIQUE NOT NULL,
    description TEXT
);

-- Capabilities dimension (License Types: APM, RUM, Synthetic, DB)
CREATE TABLE capabilities_dim (
    capability_id SERIAL PRIMARY KEY,
    capability_code TEXT UNIQUE NOT NULL,
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

-- Applications dimension (CMDB & AppD linkage)
-- FIXED: Made FK constraints optional with defaults to allow incremental population
CREATE TABLE applications_dim (
    app_id SERIAL PRIMARY KEY,
    appd_application_id INT UNIQUE,
    appd_application_name TEXT,
    sn_sys_id TEXT UNIQUE,
    sn_service_name TEXT,
    owner_id INT DEFAULT 1 REFERENCES owners_dim(owner_id), -- Default to 'Unassigned'
    sector_id INT DEFAULT 1 REFERENCES sectors_dim(sector_id), -- Default to 'Unassigned'
    architecture_id INT DEFAULT 1 REFERENCES architecture_dim(architecture_id), -- Default to 'Unknown'
    h_code TEXT,
    is_critical BOOLEAN DEFAULT FALSE,
    support_group TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes for common query patterns
CREATE INDEX idx_applications_appd_id ON applications_dim(appd_application_id);
CREATE INDEX idx_applications_sn_sys_id ON applications_dim(sn_sys_id);
CREATE INDEX idx_applications_h_code ON applications_dim(h_code);


-- ----------------------------------------------------
-- 2. CONFIGURATION TABLES
-- ----------------------------------------------------

-- Price configuration (Contract-based pricing with renewal periods)
CREATE TABLE price_config (
    price_id SERIAL PRIMARY KEY,
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    unit_rate NUMERIC NOT NULL,
    contract_renewal_date DATE
);

-- Allocation rules (Shared service cost distribution logic)
CREATE TABLE allocation_rules (
    rule_id SERIAL PRIMARY KEY,
    rule_name TEXT NOT NULL,
    distribution_method TEXT NOT NULL,
    shared_service_code TEXT,
    applies_to_sector_id INT REFERENCES sectors_dim(sector_id),
    is_active BOOLEAN DEFAULT TRUE
);

-- Mapping overrides (Manual reconciliation UI for exceptions)
CREATE TABLE mapping_overrides (
    override_id SERIAL PRIMARY KEY,
    source_system TEXT NOT NULL,
    source_key TEXT NOT NULL,
    target_table TEXT NOT NULL,
    target_field TEXT NOT NULL,
    override_value TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
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
    tier TEXT NOT NULL,
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
    method TEXT,
    PRIMARY KEY(month_start, app_id, capability_id, tier)
);

-- Chargeback fact (Monthly department charges)
CREATE TABLE chargeback_fact (
    month_start DATE NOT NULL,
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    h_code TEXT,
    sector_id INT NOT NULL REFERENCES sectors_dim(sector_id),
    owner_id INT NOT NULL REFERENCES owners_dim(owner_id),
    usd_amount NUMERIC NOT NULL,
    chargeback_cycle TEXT,
    is_finalized BOOLEAN DEFAULT FALSE,
    PRIMARY KEY(month_start, app_id)
);

-- ----------------------------------------------------
-- 4. AUDIT TABLES
-- ----------------------------------------------------

-- ETL execution log (Job history)
CREATE TABLE etl_execution_log (
    run_id SERIAL PRIMARY KEY,
    job_name TEXT NOT NULL,
    started_at TIMESTAMP DEFAULT NOW(),
    finished_at TIMESTAMP,
    status TEXT,
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
    target_pk JSONB,
    changed_fields JSONB,
    action TEXT
);

-- Reconciliation log (Matching history)
CREATE TABLE reconciliation_log (
    reconciliation_id SERIAL PRIMARY KEY,
    match_run_ts TIMESTAMP DEFAULT NOW(),
    source_a TEXT,
    source_b TEXT,
    match_key_a TEXT,
    match_key_b TEXT,
    confidence_score NUMERIC,
    match_status TEXT,
    resolved_app_id INT REFERENCES applications_dim(app_id)
);

-- User actions (Administrative changes)
CREATE TABLE user_actions (
    action_id SERIAL PRIMARY KEY,
    user_name TEXT NOT NULL,
    action_type TEXT NOT NULL,
    target_table TEXT,
    details JSONB,
    action_ts TIMESTAMP DEFAULT NOW()
);

-- ----------------------------------------------------
-- 5. ACCESS CONTROL
-- Grant privileges to devuser (ETL user)
-- ----------------------------------------------------
DO $$
DECLARE
    t RECORD;
BEGIN
    -- Grant table permissions
    FOR t IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO appd_ro;', t.table_name);
    END LOOP;

    -- Grant sequence permissions
    FOR t IN
        SELECT sequence_name
        FROM information_schema.sequences
        WHERE sequence_schema = 'public'
    LOOP
        EXECUTE format('GRANT USAGE, SELECT, UPDATE ON SEQUENCE %I TO appd_ro;', t.sequence_name);
    END LOOP;
END
$$;

-- Verification
DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Database Schema Created Successfully';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Tables created: %', (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public');
    RAISE NOTICE 'Next: Run seed scripts to populate dimension tables';
    RAISE NOTICE '==============================================';
END $$;