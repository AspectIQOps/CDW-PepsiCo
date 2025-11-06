cat > sql/init/01_init_users_and_schema.sql << 'EOF'
-- ========================================
-- Analytics Platform - Database Initialization
-- ========================================
-- Database: cost_analytics_db
-- Purpose: Multi-tool cost and usage analytics
-- Tools: AppDynamics, ServiceNow, (extensible for future tools)
-- ========================================

-- This script should be run as the postgres master user

-- ========================================
-- 1. Create Database (if not exists)
-- ========================================
-- Note: This is typically done via AWS RDS console or CLI
-- Shown here for documentation purposes
-- 
-- CREATE DATABASE cost_analytics_db;

-- ========================================
-- 2. Create Users
-- ========================================

-- ETL Service User (used by all tool pipelines)
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

-- Dashboard Read-Only User (Grafana)
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

-- ========================================
-- 3. Grant Database Permissions
-- ========================================

-- ETL user needs full access to create/modify tables
GRANT CONNECT ON DATABASE cost_analytics_db TO etl_analytics;
GRANT USAGE ON SCHEMA public TO etl_analytics;
GRANT CREATE ON SCHEMA public TO etl_analytics;

-- Grafana user needs read-only access
GRANT CONNECT ON DATABASE cost_analytics_db TO grafana_ro;
GRANT USAGE ON SCHEMA public TO grafana_ro;

-- ========================================
-- 4. Set Default Privileges
-- ========================================

-- ETL user can create and modify tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT ALL ON TABLES TO etl_analytics;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT ALL ON SEQUENCES TO etl_analytics;

-- Grafana user can read all future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT SELECT ON TABLES TO grafana_ro;

-- ========================================
-- 5. Create Extensions
-- ========================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text matching

-- ========================================
-- 6. Create Audit Table
-- ========================================

CREATE TABLE IF NOT EXISTS audit_etl_runs (
    run_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tool_name VARCHAR(50) NOT NULL,
    pipeline_stage VARCHAR(50) NOT NULL,
    start_time TIMESTAMP NOT NULL DEFAULT NOW(),
    end_time TIMESTAMP,
    status VARCHAR(20) NOT NULL,
    records_processed INTEGER,
    error_message TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

DROP INDEX IF EXISTS idx_audit_tool_time;
DROP INDEX IF EXISTS idx_audit_status;
CREATE INDEX idx_audit_tool_time ON audit_etl_runs(tool_name, start_time DESC);
CREATE INDEX idx_audit_status ON audit_etl_runs(status);

-- Grant permissions on audit table
GRANT ALL ON audit_etl_runs TO etl_analytics;
GRANT SELECT ON audit_etl_runs TO grafana_ro;

-- ========================================
-- 7. Create Metadata Table for Tools
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

-- Insert initial tools
INSERT INTO tool_configurations (tool_name, is_active, configuration)
VALUES 
    ('appdynamics', TRUE, '{"version": "1.0", "api_endpoint": "saas"}'),
    ('servicenow', TRUE, '{"version": "1.0", "api_version": "v1"}')
ON CONFLICT (tool_name) DO NOTHING;

GRANT ALL ON tool_configurations TO etl_analytics;
GRANT SELECT ON tool_configurations TO grafana_ro;
GRANT USAGE, SELECT ON SEQUENCE tool_configurations_tool_id_seq TO etl_analytics;

-- ========================================
-- Comments for Documentation
-- ========================================

COMMENT ON DATABASE cost_analytics_db IS 'Multi-tool cost and usage analytics platform';
COMMENT ON TABLE audit_etl_runs IS 'Audit trail for all ETL pipeline executions';
COMMENT ON TABLE tool_configurations IS 'Active observability tool configurations';

COMMENT ON COLUMN audit_etl_runs.tool_name IS 'Name of the observability tool (appdynamics, servicenow, elastic, etc.)';
COMMENT ON COLUMN audit_etl_runs.metadata IS 'Tool-specific execution details stored as JSON';

-- ========================================
-- Verification Queries
-- ========================================

-- List all users
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Database initialization complete!';
    RAISE NOTICE '========================================';
END
$$;

SELECT usename, usesuper, usecreatedb 
FROM pg_user 
WHERE usename IN ('etl_analytics', 'grafana_ro')
ORDER BY usename;

-- List database permissions
SELECT 
    grantee,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_name IN ('audit_etl_runs', 'tool_configurations')
ORDER BY grantee, privilege_type;

-- Show active tools
SELECT tool_name, is_active, last_successful_run
FROM tool_configurations
ORDER BY tool_name;
EOF