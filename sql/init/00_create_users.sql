-- ============================================================
-- User Creation for PepsiCo AppDynamics Licensing Database
-- Creates ETL and Grafana users with appropriate permissions
-- ============================================================

-- Create ETL application user (appd_ro)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'appd_ro') THEN
        CREATE USER appd_ro WITH PASSWORD '${DB_PASSWORD}';
        RAISE NOTICE '✅ Created user: appd_ro';
    ELSE
        RAISE NOTICE 'ℹ️  User appd_ro already exists';
    END IF;
END
$$;

-- Create Grafana read-only user (grafana_ro)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'grafana_ro') THEN
        CREATE USER grafana_ro WITH PASSWORD '${GRAFANA_DB_PASSWORD}';
        RAISE NOTICE '✅ Created user: grafana_ro';
    ELSE
        RAISE NOTICE 'ℹ️  User grafana_ro already exists';
    END IF;
END
$$;

-- Grant database connection privileges
GRANT CONNECT ON DATABASE testdb TO appd_ro;
GRANT CONNECT ON DATABASE testdb TO grafana_ro;

RAISE NOTICE '============================================';
RAISE NOTICE 'User creation complete';
RAISE NOTICE '============================================';
EOF

echo "✅ Created 00_create_users.sql"