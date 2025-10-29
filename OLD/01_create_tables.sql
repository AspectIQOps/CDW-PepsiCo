-- 01_create_tables.sql
-- Drop any existing objects to ensure a clean start

-- Drop View first (to avoid dependency conflicts)
DROP VIEW IF EXISTS license_chargeback_report;

-- Drop Fact Table (depends on Dimensions)
DROP TABLE IF EXISTS usage_fact;
DROP TABLE IF EXISTS etl_execution_log;
DROP TABLE IF EXISTS price_config;

-- Drop Dimension Tables
DROP TABLE IF EXISTS applications_dim;
DROP TABLE IF EXISTS owners_dim;
DROP TABLE IF EXISTS capabilities_dim;

-- ===============================================
-- 1. Dimension Tables
-- ===============================================

CREATE TABLE applications_dim (
    application_key SERIAL PRIMARY KEY,
    application_name VARCHAR(128) NOT NULL UNIQUE,
    current_architecture_type VARCHAR(64) NOT NULL,
    h_code VARCHAR(16) NOT NULL, -- The cost center/code
    deployment_env VARCHAR(16) NOT NULL -- e.g., 'PROD', 'DEV', 'TEST'
);
COMMENT ON TABLE applications_dim IS 'Dimension table for application metadata.';

CREATE TABLE owners_dim (
    owner_key SERIAL PRIMARY KEY,
    owner_name VARCHAR(128) NOT NULL UNIQUE,
    sector VARCHAR(64) NOT NULL -- The business sector or division
);
COMMENT ON TABLE owners_dim IS 'Dimension table for license ownership/cost allocation.';

CREATE TABLE capabilities_dim (
    capability_key SERIAL PRIMARY KEY,
    capability_name VARCHAR(128) NOT NULL UNIQUE,
    license_type VARCHAR(64) NOT NULL -- e.g., 'Per Unit', 'Subscription', 'Per User'
);
COMMENT ON TABLE capabilities_dim IS 'Dimension table for license capabilities or types.';

-- ===============================================
-- 2. Fact Table
-- ===============================================

CREATE TABLE usage_fact (
    usage_id BIGSERIAL PRIMARY KEY,
    application_key INT NOT NULL REFERENCES applications_dim(application_key),
    owner_key INT NOT NULL REFERENCES owners_dim(owner_key),
    capability_key INT NOT NULL REFERENCES capabilities_dim(capability_key),
    units_used BIGINT NOT NULL,
    load_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE usage_fact IS 'Fact table containing individual license usage records.';

-- ===============================================
-- 3. Utility/Config Tables
-- ===============================================

CREATE TABLE etl_execution_log (
    log_id SERIAL PRIMARY KEY,
    etl_run_id UUID NOT NULL,
    status VARCHAR(16) NOT NULL, -- e.g., 'SUCCESS', 'FAILED', 'RUNNING'
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE,
    records_processed INT
);
COMMENT ON TABLE etl_execution_log IS 'Log for tracking ETL job executions.';

CREATE TABLE price_config (
    price_config_id SERIAL PRIMARY KEY,
    capability_key INT NOT NULL REFERENCES capabilities_dim(capability_key) UNIQUE,
    unit_price NUMERIC(10, 4) NOT NULL,
    effective_date DATE NOT NULL
);
COMMENT ON TABLE price_config IS 'Configuration for current unit pricing per capability.';
