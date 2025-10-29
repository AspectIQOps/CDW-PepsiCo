#!/bin/bash
# Quick verification script to check database setup

set -e

echo "==========================================="
echo "🔍 PepsiCo AppDynamics DB Verification"
echo "==========================================="
echo ""

# Database connection details
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-appd_licensing}
DB_USER=${DB_USER:-appd_ro}
export PGPASSWORD=${DB_PASSWORD:-appd_pass}

echo "📊 Checking database tables..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
\echo '============================================'
\echo 'Table Row Counts:'
\echo '============================================'
SELECT 
    schemaname,
    tablename,
    (xpath('/row/cnt/text()', 
           xml_count))[1]::text::int AS row_count
FROM (
    SELECT 
        schemaname,
        tablename,
        query_to_xml(
            format('SELECT count(*) AS cnt FROM %I.%I', schemaname, tablename),
            false, true, ''
        ) AS xml_count
    FROM pg_tables
    WHERE schemaname = 'public'
    ORDER BY tablename
) t;

\echo ''
\echo '============================================'
\echo 'Dimension Tables Status:'
\echo '============================================'
SELECT 'owners_dim' as table_name, COUNT(*) as rows FROM owners_dim
UNION ALL
SELECT 'sectors_dim', COUNT(*) FROM sectors_dim
UNION ALL
SELECT 'architecture_dim', COUNT(*) FROM architecture_dim
UNION ALL
SELECT 'capabilities_dim', COUNT(*) FROM capabilities_dim
UNION ALL
SELECT 'time_dim', COUNT(*) FROM time_dim
UNION ALL
SELECT 'price_config', COUNT(*) FROM price_config;

\echo ''
\echo '============================================'
\echo 'Application Data:'
\echo '============================================'
SELECT COUNT(*) as total_applications FROM applications_dim;
SELECT COUNT(*) as apps_with_appd_id FROM applications_dim WHERE appd_application_id IS NOT NULL;
SELECT COUNT(*) as apps_with_sn_id FROM applications_dim WHERE sn_sys_id IS NOT NULL;
SELECT COUNT(*) as apps_with_h_code FROM applications_dim WHERE h_code IS NOT NULL;

\echo ''
\echo '============================================'
\echo 'ETL Execution History:'
\echo '============================================'
SELECT 
    job_name,
    started_at,
    finished_at,
    status,
    rows_ingested,
    CASE 
        WHEN error_message IS NOT NULL THEN LEFT(error_message, 50) || '...'
        ELSE 'No errors'
    END as error_summary
FROM etl_execution_log
ORDER BY started_at DESC
LIMIT 10;

\echo ''
\echo '============================================'
EOF

echo ""
echo "✅ Verification complete!"
echo ""
echo "Next steps:"
echo "  1. Run ETL: docker compose run --rm etl_snow"
echo "  2. Check logs: docker compose logs postgres"
echo "  3. Access Grafana: http://localhost:3000"
echo ""