#!/bin/bash
set -e

# --- Detect script and repo paths dynamically ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_PATH="/opt/appd-licensing/.env"

# If .env does not exist in /opt, fallback to repo root
if [[ ! -f "$ENV_PATH" ]]; then
    if [[ -f "$REPO_ROOT/.env" ]]; then
        ENV_PATH="$REPO_ROOT/.env"
        echo "⚠️ .env not found in /opt/appd-licensing, using repo .env"
    else
        echo "❌ .env file not found in /opt/appd-licensing or repo. Cannot determine DB credentials."
        exit 1
    fi
fi

# Load .env variables
export $(grep -v '^#' "$ENV_PATH" | xargs)

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
    COUNT=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM $t;" 2>/dev/null || echo "")
    if [[ "$COUNT" != "" ]]; then
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
if [[ -f "$VENV_PATH/bin/activate" ]]; then
    source "$VENV_PATH/bin/activate"
    echo "✅ Virtual environment found at $VENV_PATH"

    echo -n "Testing DB connection... "
    python - <<PYTHON_EOF
import psycopg2
import os

PG_DSN = "dbname={0} user={1} password={2} host={3} port={4}".format(
    os.getenv('DB_NAME'), os.getenv('DB_USER'), os.getenv('DB_PASSWORD'),
    os.getenv('DB_HOST','localhost'), os.getenv('DB_PORT','5432')
)
try:
    conn = psycopg2.connect(PG_DSN)
    conn.close()
    print("✅ Connection OK")
except Exception as e:
    print(f"❌ Connection failed: {e}")
PYTHON_EOF

else
    echo "❌ Virtual environment not found at $VENV_PATH"
fi

# -------------------------------
# 5️⃣ Final message
# -------------------------------
echo -e "\n🎉 ETL stack post-install check complete!"
echo "Check Grafana UI at http://<EC2_PUBLIC_IP>:3000 (default admin/admin)"
