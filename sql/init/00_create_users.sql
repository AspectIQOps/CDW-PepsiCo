-- ========================================
-- User Creation Script
-- Database: cost_analytics_db
-- ========================================

-- Create ETL service user
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

-- Create Grafana read-only user
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

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO etl_analytics;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO etl_analytics;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_ro;

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Final notice
DO $
BEGIN
    RAISE NOTICE 'User creation complete';
END
$;