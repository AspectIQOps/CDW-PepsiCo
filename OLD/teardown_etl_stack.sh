#!/bin/bash
set -e

BASE_DIR="/opt/appd-licensing"
POSTGRES_DB="appd_licensing"
POSTGRES_USER="appd_ro"

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
sudo rm -f /tmp/seed_all_tables.sql

echo "✅ Teardown complete!"
