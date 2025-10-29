#!/bin/bash
# ==========================================================
# 🧹 CDW-PepsiCo Docker Stack Teardown
# Stops and removes containers, with optional volume cleanup.

# Usage
# Default (preserve PostgreSQL + Grafana data):
# ./scripts/teardown_docker_stack.sh

# Full reset (wipe everything):
# ./scripts/teardown_docker_stack.sh --full
# ==========================================================

set -euo pipefail

echo "=============================="
echo "🧹 CDW-PepsiCo Docker Stack Teardown"
echo "=============================="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yaml"
ENV_FILE="$REPO_ROOT/.env"

[[ -f "$COMPOSE_FILE" ]] || { echo "❌ Missing docker-compose.yaml"; exit 1; }

# Stop and remove containers
echo "🛑 Stopping and removing containers..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans

# Optional volume removal
if [[ "${1:-}" == "--full" ]]; then
  echo "⚠️  Full cleanup: removing named volumes including PostgreSQL data."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
else
  echo "✅ Stack removed (volumes preserved)."
  echo "Run with '--full' to remove all volumes (including data)."
fi
