cd ~/CDW-PepsiCo

# Fetch credentials from SSM
DB_PASSWORD=$(aws ssm get-parameter --name "/aspectiq/demo/DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text)
GRAFANA_DB_PASSWORD=$(aws ssm get-parameter --name "/aspectiq/demo/GRAFANA_DB_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text)
POSTGRES_MASTER_PASSWORD=$(aws ssm get-parameter --name "/aspectiq/demo/POSTGRES_MASTER_PASSWORD" --with-decryption --region us-east-2 --query 'Parameter.Value' --output text)

# Export for psql
export PGPASSWORD="$POSTGRES_PASSWORD"

# Run initialization scripts in order
echo "📝 Running 00_create_users.sql..."
DB_PASSWORD="$DB_PASSWORD" GRAFANA_DB_PASSWORD="$GRAFANA_DB_PASSWORD" \
envsubst < sql/init/00_create_users.sql | \
psql -h grafana-test-db.cbymoaeqyga6.us-east-2.rds.amazonaws.com \
     -U postgres \
     -d testdb \
     -v ON_ERROR_STOP=1

echo ""
echo "📝 Running 01_schema.sql..."
psql -h grafana-test-db.cbymoaeqyga6.us-east-2.rds.amazonaws.com \
     -U postgres \
     -d testdb \
     -v ON_ERROR_STOP=1 \
     -f sql/init/01_schema.sql

echo ""
echo "📝 Running 02_seed_dimensions.sql..."
psql -h grafana-test-db.cbymoaeqyga6.us-east-2.rds.amazonaws.com \
     -U postgres \
     -d testdb \
     -v ON_ERROR_STOP=1 \
     -f sql/init/02_seed_dimensions.sql

echo ""
echo "📝 Running 03_materialized_views.sql..."
psql -h grafana-test-db.cbymoaeqyga6.us-east-2.rds.amazonaws.com \
     -U postgres \
     -d testdb \
     -v ON_ERROR_STOP=1 \
     -f sql/init/03_materialized_views.sql

echo ""
echo "✅ Database initialization complete!"