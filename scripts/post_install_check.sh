#!/bin/bash
set -e

echo "🔹 Running ETL stack post-install health check..."

# -------------------------------
# 1️⃣ PostgreSQL service check
# -------------------------------
echo -e "\n🗄️ Checking PostgreSQL service..."
if systemctl is-active --quiet postgresql; then
    echo "✅ PostgreSQL service is active"
else
    echo "❌ PostgreSQL service is NOT active"
fi

# -------------------------------
# 2️⃣ Check database tables
# -------------------------------
echo -e "\n📊 Checking required tables and seed data..."
TABLES=("applications_dim" "capabilities_dim" "license_usage_fact" "license_cost_fact" "chargeback_fact" "forecast_fact" "etl_execution_log" "data_lineage" "mapping_overrides" "time_dim")
for t in "${TABLES[@]}"; do
    COUNT=$(sudo -u postgres psql -d appd_licensing -tAc "SELECT COUNT(*) FROM $t;")
    if [ "$COUNT" != "" ]; then
        echo "Table $t exists with $COUNT rows"
    else
        echo "❌ Table $t does not exist or cannot be queried"
    fi
done

# -------------------------------
# 3️⃣ Grafana service check
# -------------------------------
echo -e "\n📺 Checking Grafana service..."
if systemctl is-active --quiet grafana-server; then
    echo "✅ Grafana service is active"
else
    echo "❌ Grafana service is NOT active"
fi

# -------------------------------
# 4️⃣ Python virtual environment & DB connectivity
# -------------------------------
echo -e "\n🐍 Checking Python environment and DB connectivity..."
VENV_PATH="/opt/appd-licensing/etl_env"
if [ -f "$VENV_PATH/bin/activate" ]; then
    source "$VENV_PATH/bin/activate"
    echo "✅ Virtual environment found at $VENV_PATH"

    echo -n "Testing DB connection... "
    python -c "import psycopg2; psycopg2.connect(dbname='appd_licensing', user='appd_ro', password='ChangeMe123!', host='localhost', port=5432); print('✅ Connection OK')"
else
    echo "❌ Virtual environment not found at $VENV_PATH"
fi

# -------------------------------
# 5️⃣ Final message
# -------------------------------
echo -e "\n🎉 ETL stack post-install check complete!"
echo "Check Grafana UI at http://<EC2_PUBLIC_IP>:3000 (default admin/admin)"
