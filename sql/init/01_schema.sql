-- ========================================
-- Schema Creation Script
-- Database: cost_analytics_db
-- Multi-tool cost analytics platform
-- ========================================

-- ========================================
-- EXTENSIBILITY: Tool Configuration
-- ========================================

CREATE TABLE IF NOT EXISTS tool_configurations (
    tool_id SERIAL PRIMARY KEY,
    tool_name VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    last_successful_run TIMESTAMP,
    configuration JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT valid_tool_name CHECK (tool_name ~ '^[a-z][a-z0-9_]*$')
);

COMMENT ON TABLE tool_configurations IS 'Tracks active observability tools and their configurations';
COMMENT ON COLUMN tool_configurations.tool_name IS 'Internal tool identifier (e.g., appdynamics, servicenow, elastic)';
COMMENT ON COLUMN tool_configurations.configuration IS 'Tool-specific configuration as JSON';

-- Seed initial tools
INSERT INTO tool_configurations (tool_name, display_name, is_active, configuration)
VALUES 
    ('appdynamics', 'AppDynamics', TRUE, '{"api_version": "v1", "type": "apm"}'),
    ('servicenow', 'ServiceNow', TRUE, '{"api_version": "v1", "type": "cmdb"}')
ON CONFLICT (tool_name) DO NOTHING;

-- ========================================
-- EXTENSIBILITY: Enhanced Audit Trail
-- ========================================

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

COMMENT ON TABLE audit_etl_runs IS 'Audit trail for all ETL pipeline executions across all tools';
COMMENT ON COLUMN audit_etl_runs.tool_name IS 'Which tool this ETL run was for (appdynamics, servicenow, etc)';
COMMENT ON COLUMN audit_etl_runs.metadata IS 'Tool-specific execution details as JSON';

CREATE INDEX idx_audit_tool_time ON audit_etl_runs(tool_name, start_time DESC);
CREATE INDEX idx_audit_status ON audit_etl_runs(status);
CREATE INDEX idx_audit_start_time ON audit_etl_runs(start_time DESC);

-- ========================================
-- SHARED: Dimension Tables
-- ========================================

CREATE TABLE IF NOT EXISTS shared_owners (
    owner_id SERIAL PRIMARY KEY,
    owner_name VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255),
    department VARCHAR(100),
    cost_center VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shared_sectors (
    sector_id SERIAL PRIMARY KEY,
    sector_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    parent_sector_id INTEGER REFERENCES shared_sectors(sector_id),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shared_capabilities (
    capability_id SERIAL PRIMARY KEY,
    capability_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    sector_id INTEGER REFERENCES shared_sectors(sector_id),
    created_at TIMESTAMP DEFAULT NOW()
);

-- ========================================
-- APPDYNAMICS: Application Tables
-- ========================================

CREATE TABLE IF NOT EXISTS appd_applications (
    application_id SERIAL PRIMARY KEY,
    application_name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    owner_id INTEGER REFERENCES shared_owners(owner_id),
    sector_id INTEGER REFERENCES shared_sectors(sector_id),
    capability_id INTEGER REFERENCES shared_capabilities(capability_id),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_appd_apps_owner ON appd_applications(owner_id);
CREATE INDEX idx_appd_apps_sector ON appd_applications(sector_id);

-- ========================================
-- APPDYNAMICS: License Tables
-- ========================================

CREATE TABLE IF NOT EXISTS appd_licenses (
    license_id SERIAL PRIMARY KEY,
    license_name VARCHAR(255) NOT NULL,
    license_type VARCHAR(100),
    total_units INTEGER,
    used_units INTEGER,
    available_units INTEGER,
    unit_cost DECIMAL(10,2),
    collection_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(license_name, collection_date)
);

CREATE INDEX idx_appd_lic_date ON appd_licenses(collection_date DESC);
CREATE INDEX idx_appd_lic_type ON appd_licenses(license_type);

-- ========================================
-- APPDYNAMICS: Agent Tables
-- ========================================

CREATE TABLE IF NOT EXISTS appd_agents (
    agent_id SERIAL PRIMARY KEY,
    application_id INTEGER REFERENCES appd_applications(application_id),
    agent_name VARCHAR(255) NOT NULL,
    agent_type VARCHAR(100),
    host_name VARCHAR(255),
    agent_version VARCHAR(50),
    is_enabled BOOLEAN DEFAULT TRUE,
    last_seen TIMESTAMP,
    collection_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(agent_name, collection_date)
);

CREATE INDEX idx_appd_agents_app ON appd_agents(application_id);
CREATE INDEX idx_appd_agents_date ON appd_agents(collection_date DESC);
CREATE INDEX idx_appd_agents_type ON appd_agents(agent_type);

-- ========================================
-- APPDYNAMICS: Usage Tables
-- ========================================

CREATE TABLE IF NOT EXISTS appd_usage_daily (
    usage_id SERIAL PRIMARY KEY,
    application_id INTEGER REFERENCES appd_applications(application_id),
    usage_date DATE NOT NULL,
    license_type VARCHAR(100),
    units_consumed INTEGER,
    agent_count INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(application_id, usage_date, license_type)
);

CREATE INDEX idx_appd_usage_app ON appd_usage_daily(application_id);
CREATE INDEX idx_appd_usage_date ON appd_usage_daily(usage_date DESC);

-- ========================================
-- APPDYNAMICS: Cost Tables
-- ========================================

CREATE TABLE IF NOT EXISTS appd_costs (
    cost_id SERIAL PRIMARY KEY,
    application_id INTEGER REFERENCES appd_applications(application_id),
    cost_date DATE NOT NULL,
    license_type VARCHAR(100),
    units_used INTEGER,
    unit_cost DECIMAL(10,2),
    total_cost DECIMAL(12,2),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(application_id, cost_date, license_type)
);

CREATE INDEX idx_appd_costs_app ON appd_costs(application_id);
CREATE INDEX idx_appd_costs_date ON appd_costs(cost_date DESC);

-- ========================================
-- APPDYNAMICS: Forecast Tables
-- ========================================

CREATE TABLE IF NOT EXISTS appd_cost_forecasts (
    forecast_id SERIAL PRIMARY KEY,
    application_id INTEGER REFERENCES appd_applications(application_id),
    forecast_date DATE NOT NULL,
    forecast_period VARCHAR(20),
    predicted_cost DECIMAL(12,2),
    confidence_level DECIMAL(5,2),
    model_version VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(application_id, forecast_date, forecast_period)
);

CREATE INDEX idx_appd_forecast_app ON appd_cost_forecasts(application_id);
CREATE INDEX idx_appd_forecast_date ON appd_cost_forecasts(forecast_date DESC);

-- ========================================
-- SERVICENOW: CMDB Tables
-- ========================================

CREATE TABLE IF NOT EXISTS servicenow_cmdb (
    cmdb_id SERIAL PRIMARY KEY,
    ci_name VARCHAR(255) NOT NULL,
    ci_type VARCHAR(100),
    owner_name VARCHAR(255),
    sector_name VARCHAR(100),
    capability_name VARCHAR(100),
    status VARCHAR(50),
    environment VARCHAR(50),
    last_updated TIMESTAMP,
    collection_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(ci_name, collection_date)
);

CREATE INDEX idx_snow_cmdb_owner ON servicenow_cmdb(owner_name);
CREATE INDEX idx_snow_cmdb_sector ON servicenow_cmdb(sector_name);
CREATE INDEX idx_snow_cmdb_date ON servicenow_cmdb(collection_date DESC);

-- ========================================
-- RECONCILIATION: Mapping Tables
-- ========================================

CREATE TABLE IF NOT EXISTS reconciliation_app_mapping (
    mapping_id SERIAL PRIMARY KEY,
    appd_application_name VARCHAR(255),
    snow_ci_name VARCHAR(255),
    match_confidence DECIMAL(5,2),
    match_method VARCHAR(50),
    is_verified BOOLEAN DEFAULT FALSE,
    verified_by VARCHAR(100),
    verified_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(appd_application_name, snow_ci_name)
);

CREATE INDEX idx_recon_appd ON reconciliation_app_mapping(appd_application_name);
CREATE INDEX idx_recon_snow ON reconciliation_app_mapping(snow_ci_name);

-- ========================================
-- ANALYTICS: Summary Tables
-- ========================================

CREATE TABLE IF NOT EXISTS analytics_monthly_summary (
    summary_id SERIAL PRIMARY KEY,
    month_date DATE NOT NULL,
    sector_name VARCHAR(100),
    total_applications INTEGER,
    total_agents INTEGER,
    total_cost DECIMAL(12,2),
    avg_cost_per_app DECIMAL(12,2),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(month_date, sector_name)
);

CREATE INDEX idx_analytics_month ON analytics_monthly_summary(month_date DESC);

-- ========================================
-- Grant Permissions
-- ========================================

-- ETL user gets all privileges
GRANT ALL ON ALL TABLES IN SCHEMA public TO etl_analytics;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO etl_analytics;

-- Grafana user gets read-only
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_ro;

-- Final notice
DO $
BEGIN
    RAISE NOTICE 'Schema creation complete with extensibility framework';
END
$;