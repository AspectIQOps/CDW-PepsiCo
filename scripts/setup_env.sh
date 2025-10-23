#!/bin/bash
set -e

# --- Detect paths dynamically ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
POSTGRES_DIR="$REPO_DIR/postgres"
ENV_FILE="$REPO_DIR/.env"
BASE_DIR="/opt/appd-licensing"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ .env file not found at $ENV_FILE. Please copy .env.example to .env and populate credentials."
    exit 1
fi

# --- Load .env variables ---
export $(grep -v '^#' "$ENV_FILE" | xargs)

echo "🔄 Updating system packages..."
sudo apt update && sudo apt -y upgrade

echo "🐍 Installing Python, PostgreSQL, and required tools..."
sudo apt -y install python3 python3-venv python3-pip postgresql postgresql-contrib wget curl unzip software-properties-common

echo "🗄️ Setting up PostgreSQL database and user..."
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo -u postgres psql <<SQL
DROP DATABASE IF EXISTS ${DB_NAME};
DROP ROLE IF EXISTS ${DB_USER};

CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
CREATE DATABASE ${DB_NAME} OWNER postgres;
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
    sudo -u postgres psql -d "${DB_NAME}" -f "$TMP_SQL"
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
    sudo -u postgres psql -d "${DB_NAME}" -f "$TMP_SEED"
    echo "✅ Database tables seeded successfully."
else
    echo "⚠️ Seed SQL not found at $SEED_SQL. Skipping."
fi

echo "✅ Environment setup complete!"
echo "Activate Python venv: source $BASE_DIR/etl_env/bin/activate"
echo "Check Grafana UI at http://<EC2_PUBLIC_IP>:3000 (default admin/admin)"
