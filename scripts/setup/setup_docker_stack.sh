#!/bin/bash
# ==========================================================
# 🚀 CDW-PepsiCo Docker Stack Setup
# Builds and starts the PepsiCo AppDynamics dashboard stack.
# Uses AWS SSM for secrets and on-demand ETL runners.
# ==========================================================

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

echo "=============================="
echo "🚀 Setting up CDW-PepsiCo Docker Stack"
echo "=============================="

# --- Resolve repo root (works from any directory) ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yaml"

# --- Validate essential files ---
[[ -f "$COMPOSE_FILE" ]] || { echo "❌ Missing docker-compose.yaml at $COMPOSE_FILE"; exit 1; }
# NOTE: Removed .env check. The app now relies on AWS SSM credentials.

# --- Permissions ---
echo "🔧 Setting script permissions..."
chmod +x "$REPO_ROOT"/scripts/etl/*.py 2>/dev/null || true
chmod +x "$REPO_ROOT"/docker/etl/entrypoint.sh 2>/dev/null || true
# Removed redundant cron permission set.

# --- Create required directories if missing ---
echo "📁 Ensuring essential directories exist..."
mkdir -p "$REPO_ROOT/sql/init" "$REPO_ROOT/sql/seed" "$REPO_ROOT/config/grafana" \
         "$REPO_ROOT/scripts/etl" "$REPO_ROOT/docker/etl" "$REPO_ROOT/logs"

# --- Start stack ---
echo "🐳 Building and starting Docker stack..."
# We no longer use --env-file since secrets come from SSM via the EC2 role.
docker compose -f "$COMPOSE_FILE" up -d --build

# --- Post-install check (Wait for readiness and run a test ETL) ---
if [ -f "$REPO_ROOT/scripts/utils/post_install_check.sh" ]; then
  echo "🔍 Running post-install checks..."
  # Wait for the database to be healthy before running the check
  docker compose -f "$COMPOSE_FILE" wait postgres grafana
  bash "$REPO_ROOT/scripts/utils/post_install_check.sh"
else
  echo "⚠️  post_install_check.sh not found — skipping."
fi

# --- Health summary ---
echo "✅ Docker stack startup complete!"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "🌐 Grafana should be accessible at: http://<your-ec2-public-ip>:3000"
echo " "
echo "➡️ Next Step: Configure host crontab to run ETL jobs (see setup instructions)."
