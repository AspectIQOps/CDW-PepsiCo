#!/bin/sh
# Use /bin/sh for lightweight execution inside the slim image

# Exit immediately if any command fails (ensures security check is reliable)
set -e

# Ensure Python scripts can import from each other
export PYTHONPATH=/app/scripts/etl:$PYTHONPATH

# --- Check Configuration ---
# DB_HOST and SSM_PATH are passed from docker-compose.yaml
if [ -z "$DB_HOST" ] || [ -z "$SSM_PATH" ]; then
    echo "ERROR: DB_HOST or SSM_PATH environment variable is not set. Cannot proceed."
    exit 1
fi

# ... (AWS SSM and Local Variable Check block remains unchanged) ...
# 

if [ -z "$DB_PASSWORD" ]; then
    echo "Starting ETL job setup. DB_PASSWORD not found locally. Fetching production secrets from AWS SSM path: ${SSM_PATH}"
    
    # --- Fetch Secrets from AWS SSM and Export as Environment Variables ---
    # Database Secrets
    export DB_NAME=$(aws ssm get-parameter --name "${SSM_PATH}/DB_NAME" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export DB_USER=$(aws ssm get-parameter --name "${SSM_PATH}/DB_USER" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export DB_PASSWORD=$(aws ssm get-parameter --name "${SSM_PATH}/DB_PASSWORD" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export PGPASSWORD=$DB_PASSWORD
    
    # AppDynamics Secrets
    export APPD_CONTROLLER=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CONTROLLER" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export APPD_ACCOUNT=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_ACCOUNT" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export APPD_CLIENT_ID=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CLIENT_ID" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export APPD_CLIENT_SECRET=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CLIENT_SECRET" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")

    # ServiceNow Secrets
    export SN_INSTANCE=$(aws ssm get-parameter --name "${SSM_PATH}/SN_INSTANCE" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export SN_USER=$(aws ssm get-parameter --name "${SSM_PATH}/SN_USER" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export SN_PASS=$(aws ssm get-parameter --name "${SSM_PATH}/SN_PASS" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    
    # After SSM fetch, perform a final check to ensure we got all necessary variables
    if [ -z "$DB_PASSWORD" ] || [ -z "$APPD_CLIENT_SECRET" ]; then
        echo "ERROR: Failed to fetch critical secrets (DB or APPD) from SSM. Ensure parameters exist at ${SSM_PATH} and the IAM role is correct."
        exit 1
    fi
    echo "Secrets fetched successfully."

else
    echo "Local DB_PASSWORD detected. Skipping AWS SSM fetch and using local environment variables for testing."
    echo "SSM path is available if needed: ${SSM_PATH}"
fi

# --- Wait for Postgres to be ready ---
DB_USER_FOR_READY=${DB_USER:-devuser}
echo "Waiting for database at ${DB_HOST}..."

until pg_isready -h "$DB_HOST" -p 5432 -U "$DB_USER_FOR_READY"; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 2
done
>&2 echo "Postgres is up and accessible."

# =========================================================================
# 💡 ETL EXECUTION SEQUENCE
# This section defines the order of operations for data loading and transformation.
# =========================================================================

echo "=========================================="
echo "Starting ETL pipeline execution."
echo "=========================================="

echo "Step 1: ServiceNow ETL - Loading CMDB data (applications, servers, relationships)"
python3 /app/scripts/etl/snow_etl.py || { echo "❌ ERROR: ServiceNow ETL failed."; exit 1; }

echo ""
echo "Step 2: AppDynamics ETL - Loading usage data and calculating costs"
python3 /app/scripts/etl/appd_etl.py || { echo "❌ ERROR: AppDynamics ETL failed."; exit 1; }

echo ""
echo "Step 3: Reconciliation - Fuzzy matching AppD and ServiceNow applications"
python3 /app/scripts/etl/reconciliation_engine.py || { echo "❌ ERROR: Reconciliation failed."; exit 1; }

echo ""
echo "Step 4: Advanced Forecasting - Generating 12-month projections"
python3 /app/scripts/etl/advanced_forecasting.py || { echo "❌ ERROR: Forecasting failed."; exit 1; }

echo ""
echo "Step 5: Allocation Engine - Distributing shared service costs"
python3 /app/scripts/etl/allocation_engine.py || { echo "❌ ERROR: Allocation failed."; exit 1; }

echo ""
echo "=========================================="
echo "✅ ETL Pipeline Complete!"
echo "=========================================="

# Refresh materialized views for dashboard performance
echo "Step 6: Refreshing materialized views for dashboard performance"
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME << EOF
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_cost_summary;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_app_cost_current;
EOF

if [ $? -eq 0 ]; then
    echo "✅ Materialized views refreshed successfully"
else
    echo "⚠️  Warning: Materialized view refresh failed (views may not exist yet)"
fi

echo ""
echo "Step 7: Validation - Checking data quality"
python3 /app/scripts/utils/validate_pipeline.py || echo "⚠️  Validation warnings detected"

# End of pipeline
echo ""
echo "=========================================="
echo "🎉 Pipeline execution completed!"
echo "=========================================="