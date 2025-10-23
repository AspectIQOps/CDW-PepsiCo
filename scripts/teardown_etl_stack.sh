#!/bin/bash
set -e

# --- Determine repo path dynamically ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
BASE_DIR="/opt/appd-licensing"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ .env file not found at $ENV_FILE. Cannot determine DB credentials."
    exit 1
fi

# --- Load DB credentials from .env ---
export $(grep -v '^#' "$ENV_FILE" | xargs)

POSTGRES_DB="${DB_NAME:-appd_licensing}"
POSTGRES_USER="${DB_USER:-appd_ro}"

echo "🛑 Stopping Grafana..."
sudo systemctl stop grafana-server || true
sudo systemctl disable grafana-server || true

echo "🗄️ Dropping PostgreSQL database and user..."
sudo -u postgres psql <<SQL
DROP DATABASE IF EXISTS $POSTGRES_DB;
DROP ROLE IF EXISTS $POSTGRES_USER;
SQL

echo "🐍 Removing Python virtual environment and application directory..."
sudo rm -rf "$BASE_DIR"

echo "🧹 Cleaning up temporary seed files..."
sudo rm -f /tmp/create_tables.sql /tmp/seed_all_tables.sql

echo "✅ Teardown complete!"
