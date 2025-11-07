#!/bin/bash
set -e

cd ~/CDW-PepsiCo

echo "=========================================="
echo "Database Initialization - Analytics Platform"
echo "=========================================="
echo ""

# Fetch credentials from SSM and strip any whitespace/newlines
echo "📥 Fetching credentials from SSM..."
DB_PASSWORD=$(aws ssm get-parameter --name "/pepsico/DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text | tr -d '\n\r')
GRAFANA_DB_PASSWORD=$(aws ssm get-parameter --name "/pepsico/GRAFANA_DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text | tr -d '\n\r')
POSTGRES_MASTER_PASSWORD=$(aws ssm get-parameter --name "/pepsico/DB_ADMIN_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text | tr -d '\n\r')

# Validate credentials
if [ -z "$DB_PASSWORD" ] || [ -z "$GRAFANA_DB_PASSWORD" ] || [ -z "$POSTGRES_MASTER_PASSWORD" ]; then
    echo "❌ Error: Failed to fetch credentials from SSM"
    echo "   Ensure SSM parameters exist at /pepsico/*"
    exit 1
fi

# Export for psql
export PGPASSWORD="$POSTGRES_MASTER_PASSWORD"

# Enable SSL for RDS
export PGSSLMODE=require

# Get RDS endpoint from SSM
RDS_ENDPOINT=$(aws ssm get-parameter --name "/pepsico/DB_HOST" --region us-east-2 --query 'Parameter.Value' --output text)

if [ -z "$RDS_ENDPOINT" ]; then
    echo "❌ Error: Failed to fetch DB_HOST from SSM"
    exit 1
fi

echo "✅ Credentials retrieved"
echo "   Host: $RDS_ENDPOINT"
echo "   Database: cost_analytics_db"
echo ""

# Connection parameters
PSQL_OPTS="-h $RDS_ENDPOINT -U postgres -d cost_analytics_db -v ON_ERROR_STOP=1"

# Test connection first
echo "🔌 Testing database connection..."
if psql $PSQL_OPTS -c "SELECT version();" > /dev/null 2>&1; then
    PG_VERSION=$(psql $PSQL_OPTS -tAc "SELECT version();" | head -1)
    echo "✅ Connected to: $PG_VERSION"
else
    echo "❌ Cannot connect to database"
    echo ""
    echo "Troubleshooting checklist:"
    echo "  1. RDS security group allows EC2 access (port 5432)"
    echo "  2. Database 'cost_analytics_db' exists"
    echo "  3. Master password is correct"
    echo "  4. RDS is in 'available' state"
    exit 1
fi
echo ""

# Check if SQL file exists
SQL_FILE="sql/init/00_complete_init.sql"

if [ ! -f "$SQL_FILE" ]; then
    echo "❌ Error: SQL initialization file not found"
    echo "   Expected: ~/CDW-PepsiCo/$SQL_FILE"
    echo ""
    echo "Please ensure the SQL file exists before running this script."
    exit 1
fi

# Run complete initialization
echo "🗂️  Running complete database initialization..."
echo "   File: $SQL_FILE"
echo ""

DB_PASSWORD="$DB_PASSWORD" GRAFANA_DB_PASSWORD="$GRAFANA_DB_PASSWORD" \
envsubst < "$SQL_FILE" | psql $PSQL_OPTS

echo ""

# Verify installation
echo "🔍 Verifying installation..."
echo ""

# Count tables
TABLE_COUNT=$(psql $PSQL_OPTS -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';")
echo "   ✅ Tables created: $TABLE_COUNT"

# Count users
USER_COUNT=$(psql $PSQL_OPTS -tAc "SELECT COUNT(*) FROM pg_user WHERE usename IN ('etl_analytics', 'grafana_ro');")
echo "   ✅ Users created: $USER_COUNT/2"

# Check key tables
APPS_COUNT=$(psql $PSQL_OPTS -tAc "SELECT COUNT(*) FROM applications_dim;" 2>/dev/null || echo "0")
SECTORS_COUNT=$(psql $PSQL_OPTS -tAc "SELECT COUNT(*) FROM sectors_dim;" 2>/dev/null || echo "0")
CAPS_COUNT=$(psql $PSQL_OPTS -tAc "SELECT COUNT(*) FROM capabilities_dim;" 2>/dev/null || echo "0")

echo "   ✅ Sectors seeded: $SECTORS_COUNT"
echo "   ✅ Capabilities seeded: $CAPS_COUNT"
echo "   ✅ Applications: $APPS_COUNT (will be populated by ETL)"

echo ""
echo "=========================================="
echo "✅ Database initialization complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Start ETL pipeline:"
echo "     ./platform_manager.sh start"
echo ""
echo "  2. Monitor progress:"
echo "     ./platform_manager.sh logs"
echo ""
echo "  3. Check status:"
echo "     ./platform_manager.sh status"
echo ""
