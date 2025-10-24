#!/bin/bash
# ETL stack teardown script
# Version: 2025.10.23.4
# Purpose: Stop/remove Grafana, PostgreSQL clusters, Python environment, and seed files

set -e

BASE_DIR="/opt/appd-licensing"

# --- Grafana ---
echo "🛑 Stopping Grafana service..."
if systemctl list-units --full -all | grep -q grafana-server.service; then
    sudo systemctl stop grafana-server || echo "⚠️ Could not stop Grafana service, skipping."
    sudo systemctl disable grafana-server || echo "⚠️ Could not disable Grafana service, skipping."
else
    echo "⚠️ Grafana service not found, skipping stop/disable."
fi

echo "🗑️ Removing Grafana package..."
if dpkg -l | grep -q grafana; then
    sudo apt remove -y grafana || echo "⚠️ Could not remove Grafana package, skipping."
    sudo apt purge -y grafana || echo "⚠️ Could not purge Grafana package, skipping."
    sudo rm -f /etc/apt/sources.list.d/grafana.list
    sudo rm -f /usr/share/keyrings/grafana-archive-keyring.gpg
else
    echo "⚠️ Grafana package not installed, skipping removal."
fi

# --- PostgreSQL ---
echo "🛑 Stopping PostgreSQL..."
sudo systemctl stop postgresql || echo "⚠️ PostgreSQL service not running."

echo "🗄️ Dropping all PostgreSQL databases and roles..."
# Only attempt if server is running
if pg_isready >/dev/null 2>&1; then
    sudo -u postgres psql -Atc "SELECT datname FROM pg_database WHERE datname NOT IN ('template0','template1')" | while read db; do
        echo "Dropping database $db..."
        sudo -u postgres dropdb "$db" || echo "⚠️ Could not drop database $db."
    done

    sudo -u postgres psql -Atc "SELECT rolname FROM pg_roles WHERE rolname NOT IN ('postgres')" | while read role; do
        echo "Dropping role $role..."
        sudo -u postgres dropuser "$role" || echo "⚠️ Could not drop role $role."
    done
else
    echo "⚠️ PostgreSQL server not ready; skipping DB/role drop."
fi

echo "🗑️ Dropping all PostgreSQL clusters..."
for cluster in $(pg_lsclusters -h | awk '{print $1, $2}'); do
    VERSION=$(echo $cluster | awk '{print $1}')
    NAME=$(echo $cluster | awk '{print $2}')
    echo "Dropping cluster $VERSION/$NAME..."
    sudo pg_dropcluster --stop "$VERSION" "$NAME" || echo "⚠️ Could not drop cluster $VERSION/$NAME."
done

# --- Python virtual environment and app directory ---
if [[ -d "$BASE_DIR" ]]; then
    echo "🐍 Removing Python virtual environment and application directory..."
    sudo rm -rf "$BASE_DIR"
else
    echo "⚠️ Base directory $BASE_DIR not found, skipping."
fi

# --- Clean temporary seed files ---
echo "🧹 Cleaning up temporary seed files..."
sudo rm -f /tmp/seed_all_tables.sql

echo "✅ ETL stack teardown complete!"
