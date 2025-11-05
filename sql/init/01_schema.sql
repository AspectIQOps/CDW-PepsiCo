-- ============================================================
-- PepsiCo AppDynamics Licensing Database Schema
-- Full SoW-Aligned Schema with Standard Naming (_id suffix)
-- ============================================================

-- Drop existing objects (clean slate)
DROP TABLE IF EXISTS chargeback_fact CASCADE;
DROP TABLE IF EXISTS forecast_fact CASCADE;
DROP TABLE IF EXISTS license_cost_fact CASCADE;
DROP TABLE IF EXISTS license_usage_fact CASCADE;
DROP TABLE IF EXISTS reconciliation_log CASCADE;
DROP TABLE IF EXISTS data_lineage CASCADE;
DROP TABLE IF EXISTS user_actions CASCADE;
DROP TABLE IF EXISTS mapping_overrides CASCADE;
DROP TABLE IF EXISTS allocation_rules CASCADE;
DROP TABLE IF EXISTS price_config CASCADE;
DROP TABLE IF EXISTS applications_dim CASCADE;
DROP TABLE IF EXISTS time_dim CASCADE;
DROP TABLE IF EXISTS architecture_dim CASCADE;
DROP TABLE IF EXISTS sectors_dim CASCADE;
DROP TABLE IF EXISTS capabilities_dim CASCADE;
DROP TABLE IF EXISTS owners_dim CASCADE;
DROP TABLE IF EXISTS etl_execution_log CASCADE;
DROP TABLE IF EXISTS app_server_mapping CASCADE;
DROP TABLE IF EXISTS servers_dim CASCADE;
DROP TABLE IF EXISTS forecast_models CASCADE;

DROP VIEW IF EXISTS app_cross_reference_v CASCADE;
DROP VIEW IF EXISTS app_license_summary_v CASCADE;

-- ============================================================
-- DIMENSION TABLES
-- ============================================================

-- Owners Dimension (Ownership Hierarchy)
CREATE TABLE owners_dim (
    owner_id SERIAL PRIMARY KEY,
    owner_name TEXT NOT NULL UNIQUE,
    organizational_hierarchy TEXT,
    email TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
COMMENT ON TABLE owners_dim IS 'Application owners and organizational hierarchy';

-- Sectors Dimension (Business Sectors)
CREATE TABLE sectors_dim (
    sector_id SERIAL PRIMARY KEY,
    sector_name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT NOW()
);
COMMENT ON TABLE sectors_dim IS 'Business sectors/divisions (Beverages, Frito-Lay, etc.)';

-- Architecture Dimension (Monolith vs Microservices)
CREATE TABLE architecture_dim (
    architecture_id SERIAL PRIMARY KEY,
    pattern_name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
COMMENT ON TABLE architecture_dim IS 'Architecture patterns (Monolith, Microservices, Hybrid, etc.)';

-- Capabilities Dimension (License Types)
CREATE TABLE capabilities_dim (
    capability_id SERIAL PRIMARY KEY,
    capability_code TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
COMMENT ON TABLE capabilities_dim IS 'License capability types (APM, RUM, Synthetic, DB)';

-- Time Dimension (Pre-populated for reporting)
CREATE TABLE time_dim (
    time_id SERIAL PRIMARY KEY,
    ts TIMESTAMP NOT NULL UNIQUE,
    year INT NOT NULL,
    month INT NOT NULL,
    day INT NOT NULL,
    day_name TEXT,
    month_name TEXT,
    quarter TEXT,
    yyyy_mm TEXT NOT NULL
);
CREATE INDEX idx_time_dim_ts ON time_dim(ts);
CREATE INDEX idx_time_dim_yyyy_mm ON time_dim(yyyy_mm);
COMMENT ON TABLE time_dim IS 'Time dimension for temporal analysis';

-- Applications Dimension (CMDB & AppDynamics linkage)
CREATE TABLE applications_dim (
    app_id SERIAL PRIMARY KEY,
    
    -- AppDynamics fields
    appd_application_id INT UNIQUE,
    appd_application_name TEXT,
    
    -- ServiceNow fields
    sn_sys_id TEXT UNIQUE,
    sn_service_name TEXT,
    
    -- Foreign keys with defaults to "Unassigned"
    owner_id INT DEFAULT 1 REFERENCES owners_dim(owner_id),
    sector_id INT DEFAULT 1 REFERENCES sectors_dim(sector_id),
    architecture_id INT DEFAULT 1 REFERENCES architecture_dim(architecture_id),
    
    -- Cost allocation
    h_code TEXT,
    
    -- Metadata
    is_critical BOOLEAN DEFAULT FALSE,
    support_group TEXT,
    
    -- Audit fields
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_applications_appd_id ON applications_dim(appd_application_id);
CREATE INDEX idx_applications_sn_sys_id ON applications_dim(sn_sys_id);
CREATE INDEX idx_applications_h_code ON applications_dim(h_code);
CREATE INDEX idx_applications_owner_id ON applications_dim(owner_id);
CREATE INDEX idx_applications_sector_id ON applications_dim(sector_id);
COMMENT ON TABLE applications_dim IS 'Master application registry linking AppDynamics and ServiceNow';

-- Servers Dimension (for ServiceNow cmdb_ci_server)
CREATE TABLE servers_dim (
    server_id SERIAL PRIMARY KEY,
    sn_sys_id TEXT UNIQUE NOT NULL,
    server_name TEXT,
    ip_address TEXT,
    os TEXT,
    is_virtual BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_servers_sn_sys_id ON servers_dim(sn_sys_id);
COMMENT ON TABLE servers_dim IS 'Server configuration items from ServiceNow CMDB';

-- Application-Server Mapping (for ServiceNow cmdb_rel_ci)
CREATE TABLE app_server_mapping (
    mapping_id SERIAL PRIMARY KEY,
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    server_id INT NOT NULL REFERENCES servers_dim(server_id),
    relationship_type TEXT DEFAULT 'Runs on',
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(app_id, server_id)
);
CREATE INDEX idx_app_server_app_id ON app_server_mapping(app_id);
CREATE INDEX idx_app_server_server_id ON app_server_mapping(server_id);
COMMENT ON TABLE app_server_mapping IS 'Application to server relationships from ServiceNow';

-- ============================================================
-- CONFIGURATION TABLES
-- ============================================================

-- Price Configuration (Contract-based pricing)
CREATE TABLE price_config (
    price_id SERIAL PRIMARY KEY,
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    unit_rate NUMERIC(10,4) NOT NULL,
    contract_renewal_date DATE,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_price_config_capability ON price_config(capability_id, tier);
COMMENT ON TABLE price_config IS 'Pricing rules for license types and tiers';

-- Allocation Rules (Cost distribution logic)
CREATE TABLE allocation_rules (
    rule_id SERIAL PRIMARY KEY,
    rule_name TEXT NOT NULL,
    distribution_method TEXT NOT NULL,
    shared_service_code TEXT,
    applies_to_sector_id INT REFERENCES sectors_dim(sector_id),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);
COMMENT ON TABLE allocation_rules IS 'Rules for allocating shared service costs';

-- Mapping Overrides (Manual reconciliation)
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
COMMENT ON TABLE mapping_overrides IS 'Manual overrides for data reconciliation';

-- ============================================================
-- FACT TABLES
-- ============================================================

-- License Usage Fact (Granular usage metrics)
CREATE TABLE license_usage_fact (
    usage_id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMP NOT NULL,
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL,
    units_consumed NUMERIC NOT NULL,
    nodes_count INT,
    servers_count INT,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_license_usage_ts ON license_usage_fact(ts);
CREATE INDEX idx_license_usage_app ON license_usage_fact(app_id);
CREATE INDEX idx_license_usage_capability ON license_usage_fact(capability_id);
CREATE INDEX idx_license_usage_composite ON license_usage_fact(ts, app_id, capability_id, tier);
COMMENT ON TABLE license_usage_fact IS 'Daily license usage metrics from AppDynamics';

-- License Cost Fact (Calculated costs)
CREATE TABLE license_cost_fact (
    cost_id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMP NOT NULL,
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL,
    usd_cost NUMERIC(12,2) NOT NULL,
    price_id INT REFERENCES price_config(price_id),
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_license_cost_ts ON license_cost_fact(ts);
CREATE INDEX idx_license_cost_app ON license_cost_fact(app_id);
CREATE INDEX idx_license_cost_composite ON license_cost_fact(ts, app_id, capability_id);
COMMENT ON TABLE license_cost_fact IS 'Calculated license costs with pricing attribution';

-- Forecast Fact (Prediction data)
CREATE TABLE forecast_fact (
    forecast_id BIGSERIAL PRIMARY KEY,
    month_start DATE NOT NULL,
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    capability_id INT NOT NULL REFERENCES capabilities_dim(capability_id),
    tier TEXT NOT NULL,
    projected_units NUMERIC,
    projected_cost NUMERIC(12,2),
    confidence_interval_high NUMERIC,
    confidence_interval_low NUMERIC,
    method TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
-- Add unique constraint for ON CONFLICT in advanced_forecasting.py
CREATE UNIQUE INDEX idx_forecast_fact_unique ON forecast_fact(month_start, app_id, capability_id, tier);
CREATE INDEX idx_forecast_month ON forecast_fact(month_start);
CREATE INDEX idx_forecast_app ON forecast_fact(app_id);
COMMENT ON TABLE forecast_fact IS '12-24 month license usage projections';

-- Chargeback Fact (Monthly department charges)
CREATE TABLE chargeback_fact (
    chargeback_id BIGSERIAL PRIMARY KEY,
    month_start DATE NOT NULL,
    app_id INT NOT NULL REFERENCES applications_dim(app_id),
    h_code TEXT,
    sector_id INT NOT NULL REFERENCES sectors_dim(sector_id),
    owner_id INT NOT NULL REFERENCES owners_dim(owner_id),
    usd_amount NUMERIC(12,2) NOT NULL,
    chargeback_cycle TEXT,
    is_finalized BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX idx_chargeback_fact_unique ON chargeback_fact(month_start, app_id, sector_id);
CREATE INDEX idx_chargeback_month ON chargeback_fact(month_start);
CREATE INDEX idx_chargeback_sector ON chargeback_fact(sector_id);
CREATE INDEX idx_chargeback_hcode ON chargeback_fact(h_code);
COMMENT ON TABLE chargeback_fact IS 'Monthly chargeback amounts by department';

-- ============================================================
-- AUDIT TABLES
-- ============================================================

-- ETL Execution Log
CREATE TABLE etl_execution_log (
    run_id SERIAL PRIMARY KEY,
    job_name TEXT NOT NULL,
    started_at TIMESTAMP DEFAULT NOW(),
    finished_at TIMESTAMP,
    status TEXT,
    rows_ingested INT,
    error_message TEXT
);
CREATE INDEX idx_etl_log_started ON etl_execution_log(started_at DESC);
CREATE INDEX idx_etl_log_job ON etl_execution_log(job_name, started_at DESC);
COMMENT ON TABLE etl_execution_log IS 'ETL job execution history';

-- Data Lineage (Full audit trail)
CREATE TABLE data_lineage (
    lineage_id SERIAL PRIMARY KEY,
    run_id INT REFERENCES etl_execution_log(run_id),
    source_system TEXT,
    source_endpoint TEXT,
    target_table TEXT NOT NULL,
    target_pk JSONB,
    changed_fields JSONB,
    action TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_lineage_run ON data_lineage(run_id);
CREATE INDEX idx_lineage_table ON data_lineage(target_table);
COMMENT ON TABLE data_lineage IS 'Complete audit trail of data changes';

-- Reconciliation Log (Matching history)
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
CREATE INDEX idx_recon_status ON reconciliation_log(match_status);
COMMENT ON TABLE reconciliation_log IS 'AppDynamics-ServiceNow reconciliation history';

-- User Actions (Administrative changes)
CREATE TABLE user_actions (
    action_id SERIAL PRIMARY KEY,
    user_name TEXT NOT NULL,
    action_type TEXT NOT NULL,
    target_table TEXT,
    details JSONB,
    action_ts TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_user_actions_ts ON user_actions(action_ts DESC);
COMMENT ON TABLE user_actions IS 'Audit log of user administrative actions';

-- Forecast Models (Algorithm configurations)
CREATE TABLE forecast_models (
    model_id SERIAL PRIMARY KEY,
    model_name TEXT NOT NULL UNIQUE,
    algorithm TEXT NOT NULL,
    parameters JSONB,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
COMMENT ON TABLE forecast_models IS 'Forecasting algorithm configurations and parameters';

-- ============================================================
-- VIEWS FOR GRAFANA DASHBOARDS
-- ============================================================

-- Application Cross Reference View
CREATE VIEW app_cross_reference_v AS
SELECT 
    ad.app_id,
    ad.appd_application_id,
    ad.appd_application_name,
    ad.sn_sys_id,
    ad.sn_service_name,
    o.owner_name,
    s.sector_name,
    ar.pattern_name as architecture,
    ad.h_code,
    ad.is_critical,
    ad.support_group,
    CASE 
        WHEN ad.appd_application_id IS NOT NULL AND ad.sn_sys_id IS NOT NULL THEN 'Matched'
        WHEN ad.appd_application_id IS NOT NULL THEN 'AppD Only'
        WHEN ad.sn_sys_id IS NOT NULL THEN 'ServiceNow Only'
        ELSE 'Unknown'
    END as match_status
FROM applications_dim ad
LEFT JOIN owners_dim o ON o.owner_id = ad.owner_id
LEFT JOIN sectors_dim s ON s.sector_id = ad.sector_id
LEFT JOIN architecture_dim ar ON ar.architecture_id = ad.architecture_id;

COMMENT ON VIEW app_cross_reference_v IS 'Denormalized application view for dashboards';

-- Application License Summary View
CREATE VIEW app_license_summary_v AS
SELECT 
    ad.app_id,
    COALESCE(ad.appd_application_name, ad.sn_service_name) as application_name,
    o.owner_name,
    s.sector_name,
    ar.pattern_name as architecture,
    ad.h_code,
    COUNT(DISTINCT luf.capability_id) as capability_count,
    SUM(luf.units_consumed) as total_units_consumed,
    SUM(lcf.usd_cost) as total_cost
FROM applications_dim ad
LEFT JOIN owners_dim o ON o.owner_id = ad.owner_id
LEFT JOIN sectors_dim s ON s.sector_id = ad.sector_id
LEFT JOIN architecture_dim ar ON ar.architecture_id = ad.architecture_id
LEFT JOIN license_usage_fact luf ON luf.app_id = ad.app_id
    AND luf.ts >= DATE_TRUNC('month', NOW())
LEFT JOIN license_cost_fact lcf ON lcf.app_id = ad.app_id
    AND lcf.ts >= DATE_TRUNC('month', NOW())
GROUP BY ad.app_id, ad.appd_application_name, ad.sn_service_name, 
         o.owner_name, s.sector_name, ar.pattern_name, ad.h_code;

COMMENT ON VIEW app_license_summary_v IS 'Current month license summary by application';

-- Peak vs Pro Savings Analysis View
CREATE VIEW peak_vs_pro_savings_v AS
SELECT 
    ad.app_id,
    COALESCE(ad.appd_application_name, ad.sn_service_name) as application_name,
    s.sector_name,
    cd.capability_code,
    SUM(CASE WHEN luf.tier = 'PEAK' THEN luf.units_consumed ELSE 0 END) as peak_units,
    SUM(CASE WHEN luf.tier = 'PRO' THEN luf.units_consumed ELSE 0 END) as pro_units,
    SUM(CASE WHEN luf.tier = 'PEAK' THEN lcf.usd_cost ELSE 0 END) as peak_cost,
    SUM(CASE WHEN luf.tier = 'PRO' THEN lcf.usd_cost ELSE 0 END) as pro_cost,
    -- Potential savings if all PEAK moved to PRO
    SUM(CASE WHEN luf.tier = 'PEAK' THEN lcf.usd_cost ELSE 0 END) * 0.33 as potential_savings
FROM license_usage_fact luf
JOIN applications_dim ad ON ad.app_id = luf.app_id
JOIN sectors_dim s ON s.sector_id = ad.sector_id
JOIN capabilities_dim cd ON cd.capability_id = luf.capability_id
LEFT JOIN license_cost_fact lcf ON lcf.app_id = luf.app_id 
    AND lcf.ts = luf.ts 
    AND lcf.capability_id = luf.capability_id
    AND lcf.tier = luf.tier
WHERE luf.ts >= DATE_TRUNC('month', NOW()) - INTERVAL '3 months'
GROUP BY ad.app_id, ad.appd_application_name, ad.sn_service_name, 
         s.sector_name, cd.capability_code;

COMMENT ON VIEW peak_vs_pro_savings_v IS 'Tier analysis with savings potential calculation';

-- Architecture Efficiency View
CREATE VIEW architecture_efficiency_v AS
SELECT 
    ar.pattern_name as architecture,
    COUNT(DISTINCT ad.app_id) as app_count,
    AVG(luf.units_consumed) as avg_daily_units,
    AVG(luf.nodes_count) as avg_nodes,
    AVG(luf.units_consumed) / NULLIF(AVG(luf.nodes_count), 0) as efficiency_ratio,
    SUM(lcf.usd_cost) as total_cost,
    SUM(lcf.usd_cost) / NULLIF(COUNT(DISTINCT ad.app_id), 0) as cost_per_app
FROM applications_dim ad
JOIN architecture_dim ar ON ar.architecture_id = ad.architecture_id
LEFT JOIN license_usage_fact luf ON luf.app_id = ad.app_id
    AND luf.ts >= DATE_TRUNC('month', NOW())
LEFT JOIN license_cost_fact lcf ON lcf.app_id = luf.app_id
    AND lcf.ts = luf.ts
    AND lcf.capability_id = luf.capability_id
    AND lcf.tier = luf.tier
GROUP BY ar.pattern_name;

COMMENT ON VIEW architecture_efficiency_v IS 'License efficiency metrics by architecture pattern';

-- ============================================================
-- PERMISSIONS
-- ============================================================

-- Grant permissions to appd_ro user
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
    
    -- Grant view permissions
    FOR t IN
        SELECT table_name
        FROM information_schema.views
        WHERE table_schema = 'public'
    LOOP
        EXECUTE format('GRANT SELECT ON %I TO appd_ro;', t.table_name);
    END LOOP;
END
$$;



-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Schema Creation Complete';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Tables created: %', (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE');
    RAISE NOTICE 'Views created: %', (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'public');
    RAISE NOTICE 'Next: Run 02_seed_dimensions.sql to populate defaults';
    RAISE NOTICE '==============================================';
END $$;