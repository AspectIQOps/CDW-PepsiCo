#!/bin/bash
# Database Setup Verification for EC2/RDS Environment

set -e

echo "==========================================="
echo "🔍 PepsiCo Analytics DB Verification"
echo "==========================================="
echo ""

# Fetch database connection details from SSM or use defaults
DB_HOST=${DB_HOST:-$(aws ssm get-parameter --name "/pepsico/DB_HOST" --region us-east-2 --query 'Parameter.Value' --output text 2>/dev/null || echo "pepsico-analytics-db.cbymoaeqyga6.us-east-2.rds.amazonaws.com")}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-$(aws ssm get-parameter --name "/pepsico/DB_NAME" --region us-east-2 --query 'Parameter.Value' --output text 2>/dev/null || echo "cost_analytics_db")}
DB_USER=${DB_USER:-$(aws ssm get-parameter --name "/pepsico/DB_USER" --region us-east-2 --query 'Parameter.Value' --output text 2>/dev/null || echo "etl_analytics")}

# Get password from SSM
export PGPASSWORD=${DB_PASSWORD:-$(aws ssm get-parameter --name "/pepsico/DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text 2>/dev/null)}

# Enable SSL mode for RDS
export PGSSLMODE=require

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