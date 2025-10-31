-- ============================================================
-- Create Read-Only User for Grafana Cloud
-- ============================================================
-- Run this on your PostgreSQL database to create a dedicated
-- user for Grafana Cloud with read-only access
-- ============================================================

-- Create the user
CREATE USER grafana_cloud WITH PASSWORD 'grafana_secure_pass_2024';

-- Grant connection to the database
GRANT CONNECT ON DATABASE appd_licensing TO grafana_cloud;

-- Connect to the appd_licensing database first, then run:
-- \c appd_licensing

-- Grant usage on the public schema
GRANT USAGE ON SCHEMA public TO grafana_cloud;

-- Grant SELECT on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_cloud;

-- Grant SELECT on all future tables (important for new tables)
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT SELECT ON TABLES TO grafana_cloud;

-- Grant usage on sequences (needed for some queries)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO grafana_cloud;

-- Verify permissions
\du grafana_cloud
\dp

-- Test the connection (optional)
-- psql -h localhost -U grafana_cloud -d appd_licensing -c "SELECT COUNT(*) FROM applications_dim;"