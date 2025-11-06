#!/bin/bash
# Daily Teardown - Clean Shutdown

set -e

echo "=========================================="
echo "🧹 Daily Environment Teardown"
echo "=========================================="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Stop containers
echo "🛑 Stopping Docker containers..."
docker compose -f docker-compose.ec2.yaml down -v

# Show final stats
echo ""
echo "📊 Final data summary:"

# Check if psql is available
if command -v psql &> /dev/null; then
    # Try to get database stats
    DB_HOST=$(aws ssm get-parameter --name "/pepsico/DB_HOST" --region us-east-2 --query 'Parameter.Value' --output text 2>/dev/null || echo "pepsico-analytics-db.cbymoaeqyga6.us-east-2.rds.amazonaws.com")
    DB_PASSWORD=$(aws ssm get-parameter --name "/pepsico/DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text 2>/dev/null)
    
    if [ -n "$DB_PASSWORD" ]; then
        PGPASSWORD="$DB_PASSWORD" \
        PGSSLMODE=require \
        psql -h "$DB_HOST" -U etl_analytics -d cost_analytics_db -c "
        SELECT 'Applications' as metric, COUNT(*)::text as count FROM applications_dim
        UNION ALL
        SELECT 'Usage Records', COUNT(*)::text FROM license_usage_fact
        UNION ALL
        SELECT 'Cost Records', COUNT(*)::text FROM license_cost_fact
        UNION ALL
        SELECT 'Latest Data', MAX(ts)::text FROM license_usage_fact;
        " 2>/dev/null || echo "⚠️  Could not retrieve database stats"
    else
        echo "⚠️  Could not fetch database password from SSM"
    fi
else
    echo "⚠️  psql not available - skipping database stats"
fi

echo ""
echo "✅ Environment cleaned and ready for AWS resource termination"
echo ""
echo "Next steps:"
echo "  • Terminate RDS: aws rds delete-db-instance --db-instance-identifier pepsico-analytics-db --skip-final-snapshot --region us-east-2"
echo "  • Terminate EC2: aws ec2 terminate-instances --instance-ids <INSTANCE_ID> --region us-east-2"
echo ""
echo "=========================================="