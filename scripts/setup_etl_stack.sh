#!/bin/bash
# ETL stack setup script
# Version: 2025.10.23.4
# Purpose: Install PostgreSQL, Python environment, Grafana (standard path), create DB/tables, and seed data

set -e

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="/opt/appd-licensing"
ENV_FILE="$BASE_DIR/.env"   # target copy of .env

# --- Copy .env file to /opt/appd-licensing and set safe ownership/permissions ---
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DEST="/opt/appd-licensing/.env"

# Determine appropriate owner: prefer SUDO_USER if script run with sudo
ETL_OWNER="${SUDO_USER:-$USER}"

if [[ -f "$REPO_ROOT/.env" ]]; then
    sudo cp "$REPO_ROOT/.env" "$ENV_DEST"
    sudo chown "$ETL_OWNER":"$ETL_OWNER" "$ENV_DEST"
    sudo chmod 600 "$ENV_DEST"
    echo "✅ Copied .env to $ENV_DEST (owned by $ETL_OWNER, permissions 600)"
else
    echo "⚠️ .env file not found in repo. Skipping copy to $ENV_DEST"
fi

# --- 1️⃣ Check for .env file ---
if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ .env file not found at $ENV_FILE."
    echo "Please create it before running setup. Example contents:"
    cat <<EOF
DB_NAME=db_name
DB_USER=db_username
DB_PASSWORD=db_password
DB_PORT=5432
EOF
    exit 1
fi

# --- 2️⃣ Load .env values safely ---
# Export all variables in .env
set -a
source "$ENV_FILE"
set +a

# Optional: ensure required vars exist
: "${DB_NAME:?DB_NAME not set in .env}"
: "${DB_USER:?DB_USER not set in .env}"
: "${DB_PASSWORD:?DB_PASSWORD not set in .env}"
: "${DB_PORT:?DB_PORT not set in .env}"

POSTGRES_DB="$DB_NAME"
POSTGRES_USER="$DB_USER"
POSTGRES_PASSWORD="$DB_PASSWORD"
POSTGRES_PORT="$DB_PORT"

echo "✅ Loaded .env variables from $ENV_FILE"

# --- 3️⃣ Update system packages ---
echo "🔄 Updating system packages..."
sudo apt update && sudo apt -y upgrade

echo "🐍 Installing Python and required tools..."
sudo apt -y install python3 python3-venv python3-pip postgresql postgresql-contrib wget curl unzip software-properties-common gnupg

# --- 4️⃣ Ensure PostgreSQL cluster exists and service is running ---
# Detect the default installed PostgreSQL version
PG_VERSION=$(pg_lsclusters -h | awk 'NR==1{print $1}')

# Remove existing 'main' cluster if it exists
if pg_lsclusters -h | grep -q "$PG_VERSION main"; then
    echo "⚡ Removing existing cluster $PG_VERSION/main..."
    sudo pg_dropcluster --stop "$PG_VERSION" main || true
fi

echo "⚡ Creating PostgreSQL cluster $PG_VERSION/main..."
sudo pg_createcluster "$PG_VERSION" main --start

sudo systemctl enable postgresql
sudo systemctl start postgresql

# Wait until PostgreSQL is ready
until sudo -u postgres psql -c '\q' 2>/dev/null; do
    echo "⏳ Waiting for PostgreSQL to start..."
    sleep 2
done
echo "✅ PostgreSQL is running."

# --- 5️⃣ Set up database and tables ---
sudo -u postgres psql <<SQL
DROP DATABASE IF EXISTS $POSTGRES_DB;
DROP ROLE IF EXISTS $POSTGRES_USER;

CREATE ROLE $POSTGRES_USER LOGIN PASSWORD '$POSTGRES_PASSWORD';
CREATE DATABASE $POSTGRES_DB OWNER postgres;

\c $POSTGRES_DB
CREATE SCHEMA IF NOT EXISTS public;

-- Capabilities dimension
CREATE TABLE IF NOT EXISTS capabilities_dim (
    capability_id SERIAL PRIMARY KEY,
    capability_code TEXT UNIQUE NOT NULL,
    description TEXT
);

-- Applications dimension
CREATE TABLE IF NOT EXISTS applications_dim (
    app_id SERIAL PRIMARY KEY,
    appd_application_id INT,
    appd_application_name TEXT,
    sn_sys_id TEXT,
    sn_service_name TEXT,
    h_code TEXT,
    sector TEXT
);

-- Time dimension
CREATE TABLE IF NOT EXISTS time_dim (
    ts TIMESTAMP PRIMARY KEY,
    y INT,
    m INT,
    d INT,
    yyyy_mm TEXT
);

-- License usage fact
CREATE TABLE IF NOT EXISTS license_usage_fact (
    ts TIMESTAMP NOT NULL,
    app_id INT REFERENCES applications_dim(app_id),
    capability_id INT REFERENCES capabilities_dim(capability_id),
    tier TEXT,
    units NUMERIC,
    nodes INT,
    PRIMARY KEY(ts, app_id, capability_id, tier)
);

-- License cost fact
CREATE TABLE IF NOT EXISTS license_cost_fact (
    ts TIMESTAMP,
    app_id INT REFERENCES applications_dim(app_id),
    capability_id INT REFERENCES capabilities_dim(capability_id),
    tier TEXT,
    usd_cost NUMERIC,
    PRIMARY KEY(ts, app_id, capability_id, tier)
);

-- Chargeback fact
CREATE TABLE IF NOT EXISTS chargeback_fact (
    month_start DATE,
    app_id INT REFERENCES applications_dim(app_id),
    h_code TEXT,
    sector TEXT,
    usd_amount NUMERIC,
    PRIMARY KEY(month_start, app_id)
);

-- Forecast fact
CREATE TABLE IF NOT EXISTS forecast_fact (
    month_start DATE,
    app_id INT REFERENCES applications_dim(app_id),
    capability_id INT REFERENCES capabilities_dim(capability_id),
    tier TEXT,
    projected_units NUMERIC,
    projected_cost NUMERIC,
    method TEXT,
    PRIMARY KEY(month_start, app_id, capability_id, tier)
);

-- ETL execution log
CREATE TABLE IF NOT EXISTS etl_execution_log (
    run_id SERIAL PRIMARY KEY,
    job_name TEXT,
    started_at TIMESTAMP DEFAULT now(),
    finished_at TIMESTAMP,
    status TEXT,
    rows_ingested INT
);

-- Data lineage
CREATE TABLE IF NOT EXISTS data_lineage (
    lineage_id SERIAL PRIMARY KEY,
    run_id INT REFERENCES etl_execution_log(run_id),
    source_system TEXT,
    source_endpoint TEXT,
    target_table TEXT,
    target_pk JSONB
);

-- Mapping overrides
CREATE TABLE IF NOT EXISTS mapping_overrides (
    override_id SERIAL PRIMARY KEY,
    source TEXT,
    source_key TEXT,
    h_code_override TEXT,
    sector_override TEXT
);

-- Grant permissions
GRANT CONNECT ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;
GRANT USAGE ON SCHEMA public TO $POSTGRES_USER;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $POSTGRES_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $POSTGRES_USER;
SQL

# --- 6️⃣ Python virtual environment ---
sudo mkdir -p "$BASE_DIR"
sudo chown -R "$SUDO_USER":"$SUDO_USER" "$BASE_DIR"

python3 -m venv "$BASE_DIR/etl_env"
source "$BASE_DIR/etl_env/bin/activate"
pip install --upgrade pip

# Install Python packages from requirements.txt if it exists
REPO_REQ="$REPO_ROOT/requirements.txt"
if [[ -f "$REPO_REQ" ]]; then
    echo "📦 Installing Python packages from $REPO_REQ..."
    pip install -r "$REPO_REQ"
else
    echo "📦 requirements.txt not found, installing default packages..."
    pip install requests pandas psycopg2-binary python-dotenv
fi

# --- 7️⃣ Grafana installation (standard path) ---
echo "🔧 Installing Grafana (standard package path)..."
sudo apt install -y software-properties-common wget

# Overwrite GPG key every time to avoid prompts
wget -q -O - https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

sudo apt update
sudo apt -y install grafana

sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server


# --- 8️⃣ Seed database ---
SEED_SRC="$SCRIPT_DIR/../postgres/seed_all_tables.sql"
SEED_TMP="/tmp/seed_all_tables.sql"

echo "🧹 Preparing database for seed..."
if sudo -u postgres psql -d "$POSTGRES_DB" -c '\q' 2>/dev/null; then
    echo "✅ Database connection OK"
else
    echo "❌ Database connection failed, aborting seed."
    exit 1
fi

if [[ -f "$SEED_SRC" ]]; then
    sudo cp "$SEED_SRC" "$SEED_TMP"
    sudo chown postgres:postgres "$SEED_TMP"

    echo "🚀 Running seed script..."
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$POSTGRES_DB" -f "$SEED_TMP"
    if [[ $? -eq 0 ]]; then
        echo "✅ Seed data inserted successfully."
    else
        echo "❌ Seed script failed. Check /var/log/postgresql/postgresql-*.log"
        exit 1
    fi
else
    echo "⚠️ Seed file not found at $SEED_SRC. Skipping seed step."
fi

echo "✅ ETL stack setup complete!"
echo "Test DB connection with:"
echo "source $BASE_DIR/etl_env/bin/activate && python -c 'import psycopg2; psycopg2.connect(dbname=\"$POSTGRES_DB\", user=\"$POSTGRES_USER\", password=\"$POSTGRES_PASSWORD\", host=\"localhost\", port=$POSTGRES_PORT); print(\"✅ Connection OK\")'"
