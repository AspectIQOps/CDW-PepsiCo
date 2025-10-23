#!/bin/bash
set -e

APP_DIR="/opt/appd-licensing"
SEED_SRC="/home/ubuntu/repo/postgres/seed_all_tables.sql"
SEED_DEST="$APP_DIR/postgres/seed_all_tables.sql"

echo "🔄 Updating system packages..."
sudo apt update && sudo apt -y upgrade

echo "📁 Creating application directory structure..."
sudo mkdir -p $APP_DIR/scripts
sudo mkdir -p $APP_DIR/postgres
sudo mkdir -p $APP_DIR/logs
sudo chown -R $USER:$USER $APP_DIR

echo "🐍 Installing Python, PostgreSQL, and required tools..."
sudo apt -y install python3 python3-venv python3-pip postgresql postgresql-contrib wget curl unzip software-properties-common

echo "🗄️ Setting up PostgreSQL database and user..."
sudo -u postgres psql <<'SQL'
DROP DATABASE IF EXISTS appd_licensing;
DROP ROLE IF EXISTS appd_ro;

CREATE ROLE appd_ro LOGIN PASSWORD 'ChangeMe123!';
CREATE DATABASE appd_licensing OWNER postgres;

\c appd_licensing

-- Create schemas & tables
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
GRANT CONNECT ON DATABASE appd_licensing TO appd_ro;
GRANT USAGE ON SCHEMA public TO appd_ro;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appd_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appd_ro;
SQL

echo "🐍 Setting up Python virtual environment..."
python3 -m venv $APP_DIR/etl_env
source $APP_DIR/etl_env/bin/activate
pip install --upgrade pip
pip install requests pandas psycopg2-binary python-dotenv

echo "📦 Installing Grafana..."
if ! grep -q "packages.grafana.com" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
    wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
    sudo apt update
fi
sudo apt -y install grafana

echo "🔹 Enabling and starting Grafana..."
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "📥 Preparing seed script..."
if [ -f "$SEED_SRC" ]; then
    echo "📦 Copying seed file from repo to $SEED_DEST..."
    sudo mkdir -p "$(dirname "$SEED_DEST")"
    sudo cp "$SEED_SRC" "$SEED_DEST"
    sudo chown postgres:postgres "$SEED_DEST"
else
    echo "⚠️ No seed file found in repo at $SEED_SRC"
fi

echo "🌱 Running seed script..."
if [ -f "$SEED_DEST" ]; then
    echo "Found seed file at $SEED_DEST. Seeding database..."
    sudo -u postgres psql -d appd_licensing -f "$SEED_DEST"
    echo "✅ Database seeded successfully."
else
    echo "⚠️ Seed file not found at $SEED_DEST. Skipping seed step."
fi

echo "🔍 Running ETL stack health check..."
POSTGRES_STATUS=$(sudo systemctl is-active postgresql)
GRAFANA_STATUS=$(sudo systemctl is-active grafana-server)
PYTHON_VERSION=$(python3 --version)

echo "PostgreSQL service: $POSTGRES_STATUS"
echo "Grafana service: $GRAFANA_STATUS"
echo "Python version: $PYTHON_VERSION"

echo "✅ ETL stack setup complete!"
echo "To test database connectivity, run:"
echo "source $APP_DIR/etl_env/bin/activate && python -c 'import psycopg2; psycopg2.connect(dbname=\"appd_licensing\", user=\"appd_ro\", password=\"ChangeMe123!\", host=\"localhost\", port=5432); print(\"✅ Database connection OK\")'"
