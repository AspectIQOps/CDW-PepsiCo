#!/bin/bash
set -e

# --- Detect paths dynamically ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POSTGRES_DIR="$PROJECT_ROOT/postgres"
BASE_DIR="/opt/appd-licensing"

echo "🔄 Updating system packages..."
sudo apt update && sudo apt -y upgrade

echo "🐍 Installing Python and required tools..."
sudo apt -y install python3 python3-venv python3-pip postgresql postgresql-contrib wget curl unzip software-properties-common

echo "🗄️ Setting up PostgreSQL database and user..."
sudo -u postgres psql <<'SQL'
DROP DATABASE IF EXISTS appd_licensing;
DROP ROLE IF EXISTS appd_ro;

CREATE ROLE appd_ro LOGIN PASSWORD 'ChangeMe123!';
CREATE DATABASE appd_licensing OWNER postgres;
SQL

echo "🐍 Setting up Python virtual environment..."
sudo mkdir -p "$BASE_DIR"
sudo chown -R "$SUDO_USER":"$SUDO_USER" "$BASE_DIR"
python3 -m venv "$BASE_DIR/etl_env"
source "$BASE_DIR/etl_env/bin/activate"
pip install --upgrade pip
pip install requests pandas psycopg2-binary python-dotenv

echo "🔧 Installing Grafana..."
sudo add-apt-repository -y "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo apt update
sudo apt -y install grafana

echo "🔹 Enable and start Grafana..."
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# --- Create DB tables ---
TABLE_SQL="$POSTGRES_DIR/create_tables.sql"
if [[ -f "$TABLE_SQL" ]]; then
    TMP_SQL="/tmp/create_tables.sql"
    cp "$TABLE_SQL" "$TMP_SQL"
    sudo chown postgres:postgres "$TMP_SQL"
    echo "🌱 Creating database tables..."
    sudo -u postgres psql -d appd_licensing -f "$TMP_SQL"
    echo "✅ Database tables created successfully."
else
    echo "⚠️ Table creation SQL not found at $TABLE_SQL. Skipping."
fi

# --- Seed DB tables ---
SEED_SQL="$POSTGRES_DIR/seed_all_tables.sql"
if [[ -f "$SEED_SQL" ]]; then
    TMP_SEED="/tmp/seed_all_tables.sql"
    cp "$SEED_SQL" "$TMP_SEED"
    sudo chown postgres:postgres "$TMP_SEED"
    echo "🌱 Seeding database tables..."
    sudo -u postgres psql -d appd_licensing -f "$TMP_SEED"
    echo "✅ Database tables seeded successfully."
else
    echo "⚠️ Seed SQL not found at $SEED_SQL. Skipping."
fi

echo "✅ Environment setup complete!"
echo "Activate Python venv: source $BASE_DIR/etl_env/bin/activate"
