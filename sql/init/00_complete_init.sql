-- ========================================
-- COMPLETE Database Initialization
-- Analytics Platform - cost_analytics_db
-- ========================================
-- This file contains EVERYTHING needed:
-- 1. Users and permissions
-- 2. Extensions
-- 3. All dimension tables
-- 4. All fact tables
-- 5. Audit and configuration tables
-- 6. Initial seed data
-- 7. Indexes and constraints
-- ========================================

-- ========================================
-- 1. CREATE USERS
-- ========================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'etl_analytics') THEN
        CREATE USER etl_analytics WITH PASSWORD '${DB_PASSWORD}';
        RAISE NOTICE 'Created user: etl_analytics';
    ELSE
        RAISE NOTICE 'User etl_analytics already exists';
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'grafana_ro') THEN
        CREATE USER grafana_ro WITH PASSWORD '${GRAFANA_DB_PASSWORD}';
        RAISE NOTICE 'Created user: grafana_ro';
    ELSE
        RAISE NOTICE 'User grafana_ro already exists';
    END IF;
END
$$;

-- Grant database connection
GRANT CONNECT ON DATABASE cost_analytics_db TO etl_analytics;
GRANT CONNECT ON DATABASE cost_analytics_db TO grafana_ro;

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO etl_analytics;
GRANT USAGE ON SCHEMA public TO grafana_ro;
GRANT CREATE ON SCHEMA public TO etl_analytics;

-- ========================================
-- 2. CREATE EXTENSIONS
-- ========================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ========================================
-- 3. AUDIT AND CONFIGURATION TABLES
-- ========================================

CREATE TABLE IF NOT EXISTS tool_configurations (
    tool_id SERIAL PRIMARY KEY,
    tool_name VARCHAR(50) UNIQUE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_successful_run TIMESTAMP,
    configuration JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_etl_runs (
    run_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tool_name VARCHAR(50) NOT NULL,
    pipeline_stage VARCHAR(50) NOT NULL,
    start_time TIMESTAMP NOT NULL DEFAULT NOW(),
    end_time TIMESTAMP,
    status VARCHAR(20) NOT NULL,
    records_processed INTEGER,
    records_inserted INTEGER,
    records_updated INTEGER,
    records_failed INTEGER,
    error_message TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT valid_status CHECK (status IN ('running', 'success', 'failed', 'partial'))
);

CREATE INDEX IF NOT EXISTS idx_audit_tool_time ON audit_etl_runs(tool_name, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_audit_status ON audit_etl_runs(status);

-- Seed initial tools
INSERT INTO tool_configurations (tool_name, is_active, configuration)
VALUES 
    ('appdynamics', TRUE, '{"version": "1.0", "api_endpoint": "saas"}'),
    ('servicenow', TRUE, '{"version": "1.0", "api_version": "v1"}')
ON CONFLICT (tool_name) DO NOTHING;

-- ========================================
-- 4. DIMENSION TABLES
-- ========================================

-- Owners (application owners/managers)
CREATE TABLE IF NOT EXISTS owners_dim (
    owner_id SERIAL PRIMARY KEY,
    owner_name VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255),
    department VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Sectors (business units)
CREATE TABLE IF NOT EXISTS sectors_dim (
    sector_id SERIAL PRIMARY KEY,
    sector_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Architecture patterns
CREATE TABLE IF NOT EXISTS architecture_dim (
    architecture_id SERIAL PRIMARY KEY,
    pattern_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Capabilities (license types)
CREATE TABLE IF NOT EXISTS capabilities_dim (
    capability_id SERIAL PRIMARY KEY,
    capability_code VARCHAR(50) UNIQUE NOT NULL,
    capability_name VARCHAR(100),
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Servers (from ServiceNow)
CREATE TABLE IF NOT EXISTS servers_dim (
    server_id SERIAL PRIMARY KEY,
    sn_sys_id VARCHAR(50) UNIQUE NOT NULL,
    server_name VARCHAR(255),
    ip_address VARCHAR(50),
    os VARCHAR(100),
    is_virtual BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Applications (merged AppD + ServiceNow data)
CREATE TABLE IF NOT EXISTS applications_dim (
    app_id SERIAL PRIMARY KEY,
    appd_application_id VARCHAR(100) UNIQUE,
    appd_application_name VARCHAR(255),
    sn_sys_id VARCHAR(50) UNIQUE,
    sn_service_name VARCHAR(255),
    h_code VARCHAR(50),
    owner_id INTEGER REFERENCES owners_dim(owner_id),
    sector_id INTEGER REFERENCES sectors_dim(sector_id),
    architecture_id INTEGER REFERENCES architecture_dim(architecture_id),
    support_group VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_apps_appd_name ON applications_dim(appd_application_name);
CREATE INDEX IF NOT EXISTS idx_apps_sn_name ON applications_dim(sn_service_name);
CREATE INDEX IF NOT EXISTS idx_apps_owner ON applications_dim(owner_id);
CREATE INDEX IF NOT EXISTS idx_apps_sector ON applications_dim(sector_id);

-- Application-Server Mapping
CREATE TABLE IF NOT EXISTS app_server_mapping (
    mapping_id SERIAL PRIMARY KEY,
    app_id INTEGER REFERENCES applications_dim(app_id) ON DELETE CASCADE,
    server_id INTEGER REFERENCES servers_dim(server_id) ON DELETE CASCADE,
    relationship_type VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(app_id, server_id)
);

-- ========================================
-- 5. CONFIGURATION TABLES
-- ========================================

-- Price configuration for license costs
CREATE TABLE IF NOT EXISTS price_config (
    price_id SERIAL PRIMARY KEY,
    capability_id INTEGER REFERENCES capabilities_dim(capability_id),
    tier VARCHAR(20) NOT NULL,
    unit_rate DECIMAL(10,4) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(capability_id, tier, start_date)
);

-- Allocation rules for shared services
CREATE TABLE IF NOT EXISTS allocation_rules (
    rule_id SERIAL PRIMARY KEY,
    rule_name VARCHAR(255) UNIQUE NOT NULL,
    distribution_method VARCHAR(50) NOT NULL,
    shared_service_code VARCHAR(50),
    applies_to_sector_id INTEGER REFERENCES sectors_dim(sector_id),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ========================================
-- 6. FACT TABLES
-- ========================================

-- License usage (raw consumption data)
CREATE TABLE IF NOT EXISTS license_usage_fact (
    usage_id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMP NOT NULL,
    app_id INTEGER REFERENCES applications_dim(app_id),
    capability_id INTEGER REFERENCES capabilities_dim(capability_id),
    tier VARCHAR(20),
    units_consumed DECIMAL(12,2),
    nodes_count INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(ts, app_id, capability_id, tier)
);

CREATE INDEX IF NOT EXISTS idx_usage_ts ON license_usage_fact(ts DESC);
CREATE INDEX IF NOT EXISTS idx_usage_app ON license_usage_fact(app_id);

-- License costs (calculated from usage * price)
CREATE TABLE IF NOT EXISTS license_cost_fact (
    cost_id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMP NOT NULL,
    app_id INTEGER REFERENCES applications_dim(app_id),
    capability_id INTEGER REFERENCES capabilities_dim(capability_id),
    tier VARCHAR(20),
    usd_cost DECIMAL(12,2),
    price_id INTEGER REFERENCES price_config(price_id),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(ts, app_id, capability_id, tier)
);

CREATE INDEX IF NOT EXISTS idx_cost_ts ON license_cost_fact(ts DESC);
CREATE INDEX IF NOT EXISTS idx_cost_app ON license_cost_fact(app_id);

-- Chargeback (monthly aggregated costs by sector)
CREATE TABLE IF NOT EXISTS chargeback_fact (
    chargeback_id SERIAL PRIMARY KEY,
    month_start DATE NOT NULL,
    app_id INTEGER REFERENCES applications_dim(app_id),
    h_code VARCHAR(50),
    sector_id INTEGER REFERENCES sectors_dim(sector_id),
    owner_id INTEGER REFERENCES owners_dim(owner_id),
    usd_amount DECIMAL(12,2),
    chargeback_cycle VARCHAR(50) DEFAULT 'monthly',
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(month_start, app_id, sector_id)
);

CREATE INDEX IF NOT EXISTS idx_chargeback_month ON chargeback_fact(month_start DESC);
CREATE INDEX IF NOT EXISTS idx_chargeback_sector ON chargeback_fact(sector_id);

-- Forecasts (predicted future usage/costs)
CREATE TABLE IF NOT EXISTS forecast_fact (
    forecast_id SERIAL PRIMARY KEY,
    month_start DATE NOT NULL,
    app_id INTEGER REFERENCES applications_dim(app_id),
    capability_id INTEGER REFERENCES capabilities_dim(capability_id),
    tier VARCHAR(20),
    projected_units DECIMAL(12,2),
    projected_cost DECIMAL(12,2),
    confidence_interval_low DECIMAL(12,2),
    confidence_interval_high DECIMAL(12,2),
    method VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(month_start, app_id, capability_id, tier)
);

CREATE INDEX IF NOT EXISTS idx_forecast_month ON forecast_fact(month_start DESC);
CREATE INDEX IF NOT EXISTS idx_forecast_app ON forecast_fact(app_id);

-- ========================================
-- 7. RECONCILIATION TABLES
-- ========================================

CREATE TABLE IF NOT EXISTS reconciliation_log (
    log_id SERIAL PRIMARY KEY,
    source_a VARCHAR(50),
    source_b VARCHAR(50),
    match_key_a VARCHAR(255),
    match_key_b VARCHAR(255),
    confidence_score DECIMAL(5,2),
    match_status VARCHAR(50),
    resolved_app_id INTEGER REFERENCES applications_dim(app_id),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recon_status ON reconciliation_log(match_status);

-- Legacy ETL execution log (for backwards compatibility)
CREATE TABLE IF NOT EXISTS etl_execution_log (
    run_id SERIAL PRIMARY KEY,
    job_name VARCHAR(100),
    started_at TIMESTAMP DEFAULT NOW(),
    finished_at TIMESTAMP,
    status VARCHAR(20),
    rows_ingested INTEGER,
    error_message TEXT
);

-- ========================================
-- 8. SEED DIMENSION DATA
-- ========================================

-- Seed owners
INSERT INTO owners_dim (owner_name, email, department) VALUES
    ('Unassigned', NULL, NULL),
    ('Platform Team', 'platform@pepsico.com', 'IT Operations'),
    ('AppDynamics Admin', 'appd-admin@pepsico.com', 'Observability')
ON CONFLICT (owner_name) DO NOTHING;

-- Seed sectors
INSERT INTO sectors_dim (sector_name, description) VALUES
    ('Unassigned', 'Applications without assigned sector'),
    ('Finance', 'Financial systems and reporting'),
    ('Supply Chain', 'Supply chain management'),
    ('Sales', 'Sales and CRM systems'),
    ('IT Operations', 'Internal IT infrastructure'),
    ('Corporate/Shared Services', 'Shared enterprise services'),
    ('Global IT', 'Global IT platform services')
ON CONFLICT (sector_name) DO NOTHING;

-- Seed architecture patterns
INSERT INTO architecture_dim (pattern_name, description) VALUES
    ('Unknown', 'Architecture not classified'),
    ('Monolithic', 'Single-tier monolithic application'),
    ('Microservices', 'Distributed microservices architecture'),
    ('Serverless', 'Serverless/FaaS architecture'),
    ('Legacy', 'Legacy mainframe or client-server')
ON CONFLICT (pattern_name) DO NOTHING;

-- Seed capabilities (AppDynamics license types)
INSERT INTO capabilities_dim (capability_code, capability_name, description) VALUES
    ('APM', 'Application Performance Monitoring', 'APM agent licensing'),
    ('MRUM', 'Mobile Real User Monitoring', 'Mobile RUM licensing'),
    ('BRUM', 'Browser Real User Monitoring', 'Browser RUM licensing'),
    ('ANALYTICS', 'Analytics', 'Analytics platform licensing'),
    ('INFRA', 'Infrastructure Monitoring', 'Infrastructure visibility')
ON CONFLICT (capability_code) DO NOTHING;

-- Seed price configuration (example rates)
INSERT INTO price_config (capability_id, tier, unit_rate, start_date) VALUES
    ((SELECT capability_id FROM capabilities_dim WHERE capability_code = 'APM'), 'PEAK', 0.75, '2024-01-01'),
    ((SELECT capability_id FROM capabilities_dim WHERE capability_code = 'APM'), 'PRO', 0.50, '2024-01-01'),
    ((SELECT capability_id FROM capabilities_dim WHERE capability_code = 'MRUM'), 'PEAK', 0.60, '2024-01-01'),
    ((SELECT capability_id FROM capabilities_dim WHERE capability_code = 'MRUM'), 'PRO', 0.40, '2024-01-01'),
    ((SELECT capability_id FROM capabilities_dim WHERE capability_code = 'BRUM'), 'PEAK', 0.55, '2024-01-01'),
    ((SELECT capability_id FROM capabilities_dim WHERE capability_code = 'BRUM'), 'PRO', 0.35, '2024-01-01')
ON CONFLICT (capability_id, tier, start_date) DO NOTHING;

-- ========================================
-- 9. GRANT PERMISSIONS
-- ========================================

-- ETL user gets all privileges
GRANT ALL ON ALL TABLES IN SCHEMA public TO etl_analytics;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO etl_analytics;

-- Grafana user gets read-only
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_ro;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO etl_analytics;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO etl_analytics;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_ro;

-- ========================================
-- 10. VERIFICATION
-- ========================================

DO $$
DECLARE
    table_count INTEGER;
    user_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO table_count 
    FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
    
    SELECT COUNT(*) INTO user_count 
    FROM pg_user 
    WHERE usename IN ('etl_analytics', 'grafana_ro');
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Database Initialization Complete!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Tables created: %', table_count;
    RAISE NOTICE 'Users created: %/2', user_count;
    RAISE NOTICE 'Extensions: uuid-ossp, pg_trgm';
    RAISE NOTICE '========================================';
END
$$;
