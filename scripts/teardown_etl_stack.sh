#!/usr/bin/env bash
set -euo pipefail

echo "⚠️  Starting teardown of AppDynamics Licensing ETL stack..."
echo "This will stop containers, drop the database, and remove /opt/appd-licensing."
read -p "Continue? (y/N): " confirm
if [[ "${confirm,,}" != "y" ]]; then
  echo "❌ Teardown aborted."
  exit 0
fi

#----------------------------------------------------------
# 1. Stop and remove Docker containers
#----------------------------------------------------------
if [ -d "/opt/appd-licensing/CDW-PepsiCo/docker" ]; then
  echo "🐳 Stopping Docker services..."
  cd /opt/appd-licensing/CDW-PepsiCo/docker
  sudo docker compose down -v || true
else
  echo "⚠️  Docker directory not found — skipping container cleanup."
fi

#----------------------------------------------------------
# 2. Drop PostgreSQL database and user
#----------------------------------------------------------
echo "🐘 Dropping database and user..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS appd_licensing;" || true
sudo -u postgres psql -c "DROP USER IF EXISTS appd_user;" || true

#----------------------------------------------------------
# 3. Remove application directories
#----------------------------------------------------------
echo "🗑️  Removing application directories..."
sudo rm -rf /opt/appd-licensing

#----------------------------------------------------------
# 4. Clean up temporary files
#----------------------------------------------------------
echo "🧼 Cleaning up temporary files..."
sudo rm -f /tmp/seed_all_tables.sql

#----------------------------------------------------------
# 5. Optional package cleanup (comment out if not desired)
#----------------------------------------------------------
# echo "🧹 Removing optional packages (Docker, Postgres, etc.)..."
# sudo apt-get remove --purge -y docker-compose docker.io postgresql postgresql-contrib python3-pip || true
# sudo apt-get autoremove -y

echo "✅ Teardown complete. System cleaned."
