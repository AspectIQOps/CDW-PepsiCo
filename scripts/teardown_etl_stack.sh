#!/bin/bash
set -e

BASE_DIR="/opt/appd-licensing"
ENV_FILE="$BASE_DIR/.env"

# -------------------------------
# 0️⃣ Load .env
# -------------------------------
if [[ -f "$ENV_FILE" ]]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
    echo "✅ Loaded environment variables from $ENV_FILE"
else
    echo "❌ .env file not found at $ENV_FILE. Cannot determine DB credentials."
    exit 1
fi

echo "🛑 Stopping Grafana..."
sudo systemctl stop grafana-server || true
sudo systemctl disable grafana-server || true

echo "🗄️ Dropping PostgreSQL database and user..."
sudo -u postgres psql <<SQL
DROP DATABASE IF EXISTS $DB_NAME;
DROP ROLE IF EXISTS $DB_USER;
SQL

echo "🐍 Removing Python virtual environment and application directory..."
sudo rm -rf "$BASE_DIR"

echo "🧹 Cleaning up temporary seed files..."
sudo rm -f /tmp/seed_all_tables.sql /tmp/create_tables.sql

echo "✅ Teardown complete!"
