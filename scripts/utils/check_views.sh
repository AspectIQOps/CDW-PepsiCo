#!/bin/bash
#
# Check Materialized Views Status
#

set -e

AWS_REGION="${AWS_REGION:-us-east-2}"

# Fetch credentials from SSM
echo "Fetching database credentials..."
export DB_HOST=$(aws ssm get-parameter --name /pepsico/DB_HOST --region $AWS_REGION --query 'Parameter.Value' --output text)
export DB_PASSWORD=$(aws ssm get-parameter --name /pepsico/DB_PASSWORD --with-decryption --region $AWS_REGION --query 'Parameter.Value' --output text)

echo "Checking materialized views in cost_analytics_db..."
echo ""

export PGPASSWORD="$DB_PASSWORD"

echo "========================================="
echo "MATERIALIZED VIEWS STATUS"
echo "========================================="
psql -h $DB_HOST -U etl_analytics -d cost_analytics_db << 'EOF'
SELECT
    schemaname as schema,
    matviewname as view_name,
    matviewowner as owner,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||matviewname)) as size
FROM pg_matviews
WHERE schemaname = 'public'
ORDER BY matviewname;
EOF

echo ""
echo "========================================="
echo "VIEW ROW COUNTS"
echo "========================================="
psql -h $DB_HOST -U etl_analytics -d cost_analytics_db << 'EOF'
DO $$
DECLARE
    v_name TEXT;
    v_count BIGINT;
BEGIN
    FOR v_name IN
        SELECT matviewname
        FROM pg_matviews
        WHERE schemaname = 'public'
        ORDER BY matviewname
    LOOP
        EXECUTE 'SELECT COUNT(*) FROM ' || v_name INTO v_count;
        RAISE NOTICE '  % ..................... % rows', RPAD(v_name, 35), v_count;
    END LOOP;
END $$;
EOF

echo ""
echo "Done!"
