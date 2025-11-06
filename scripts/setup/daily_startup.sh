cat > scripts/setup/daily_startup.sh << 'EOF'
#!/bin/bash
# Daily Startup - Complete Environment Setup

set -e

echo "=========================================="
echo "🚀 Daily Environment Startup"
echo "=========================================="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Pull latest code
echo "📥 Pulling latest code from repository..."
git pull origin deploy-docker 2>/dev/null || {
    echo "⚠️  Git pull failed or no changes - using local code"
}

# Run health check
echo ""
echo "🏥 Running system health check..."
./scripts/utils/health_check.sh

# Check if database needs initialization
echo ""
echo "🗄️  Checking database state..."

DB_PASSWORD=$(aws ssm get-parameter --name "/pepsico/DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text | tr -d '\n\r')
DB_HOST=$(aws ssm get-parameter --name "/pepsico/DB_HOST" --region us-east-2 --query 'Parameter.Value' --output text)

# Check if audit_etl_runs table exists (indicates initialized database)
PGPASSWORD="$DB_PASSWORD" \
PGSSLMODE=require \
TABLE_EXISTS=$(psql -h "$DB_HOST" -U etl_analytics -d cost_analytics_db -tAc \
  "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name='audit_etl_runs');" 2>/dev/null || echo "false")

if [ "$TABLE_EXISTS" = "t" ]; then
    echo "✅ Database already initialized, skipping initialization"
else
    echo "📝 Database not initialized, running initialization..."
    ./scripts/setup/sql_initialization.sh
fi

# Build and run ETL pipeline
echo ""
echo "⚙️  Building and running ETL pipeline..."
docker compose -f docker-compose.ec2.yaml up --build

# Verify setup
echo ""
echo "✅ Running final verification..."
./scripts/utils/verify_setup.sh

echo ""
echo "=========================================="
echo "🎉 Daily startup complete!"
echo ""
echo "Next steps:"
echo "  • Access Grafana to view dashboards"
echo "  • Run validation: python3 scripts/utils/validate_pipeline.py"
echo "  • Check logs: docker logs pepsico-etl-analytics"
echo ""
echo "=========================================="
EOF

chmod +x scripts/setup/daily_startup.sh