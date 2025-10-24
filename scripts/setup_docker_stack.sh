#!/bin/bash
# 🚀 CDW-PepsiCo Docker Stack Setup
# Builds and starts Docker stack, sets file permissions

# Determine repo root dynamically
REPO_ROOT=$(dirname "$(realpath "$0")")/..

echo "=============================="
echo "🚀 CDW-PepsiCo Docker Stack Setup"
echo "=============================="

# Ensure entrypoint and cron scripts are executable
echo "🔧 Setting executable permissions for ETL scripts..."
chmod +x "$REPO_ROOT/scripts/"*
chmod +x "$REPO_ROOT/docker/etl/entrypoint.sh"
chmod 0644 "$REPO_ROOT/docker/etl/etl_cron"

# Optional: run post-install checks
"$REPO_ROOT/scripts/post_install_check.sh"

echo "Press Enter to continue with Docker stack setup, or Ctrl+C to cancel..."
read

# Run docker-compose
echo "🐳 Starting Docker stack..."
docker compose -f "$REPO_ROOT/docker/docker-compose.yaml" --env-file "$REPO_ROOT/.env" up -d --build

echo "✅ Docker stack startup complete!"
echo "Use 'docker ps' to check running containers."
