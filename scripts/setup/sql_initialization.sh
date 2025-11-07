#!/bin/bash
set -e

cd ~/CDW-PepsiCo

# Fetch credentials from SSM and strip any whitespace/newlines
DB_PASSWORD=$(aws ssm get-parameter --name "/pepsico/DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text | tr -d '\n\r')
GRAFANA_DB_PASSWORD=$(aws ssm get-parameter --name "/pepsico/GRAFANA_DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text | tr -d '\n\r')
POSTGRES_MASTER_PASSWORD=$(aws ssm get-parameter --name "/pepsico/DB_ADMIN_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text | tr -d '\n\r')

# Export for psql
export PGPASSWORD="$POSTGRES_MASTER_PASSWORD"

# Enable SSL for RDS
export PGSSLMODE=require

# Get RDS endpoint from SSM or use default
RDS_ENDPOINT=${RDS_ENDPOINT:-$(aws ssm get-parameter --name "/pepsico/DB_HOST" --region us-east-2 --query 'Parameter.Value' --output text)}

# Connection parameters
PSQL_OPTS="-h $RDS_ENDPOINT -U postgres -d cost_analytics_db -v ON_ERROR_STOP=1"

# Run initialization script
echo "📝 Initializing database users and base tables..."
DB_PASSWORD="$DB_PASSWORD" GRAFANA_DB_PASSWORD="$GRAFANA_DB_PASSWORD" \
envsubst < sql/init/01_init_users_and_schema.sql | psql $PSQL_OPTS

echo ""
echo "✅ Database initialization complete!"
