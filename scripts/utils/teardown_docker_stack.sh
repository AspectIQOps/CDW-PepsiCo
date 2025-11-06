#!/bin/bash
# ==========================================================
# Docker Stack Teardown for EC2/RDS Environment
# Stops and removes containers, with optional volume cleanup
# ==========================================================

set -euo pipefail

echo "=============================="
echo "🧹 Docker Stack Teardown"
echo "=============================="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

COMPOSE_FILE="docker-compose.ec2.yaml"

# Check if compose file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "❌ Error: $COMPOSE_FILE not found"
    exit 1
fi

# Stop and remove containers
echo "🛑 Stopping containers..."
docker compose -f "$COMPOSE_FILE" down --remove-orphans

# Optional: Remove volumes
if [[ "${1:-}" == "--full" ]]; then
    echo "⚠️  Removing volumes..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
    echo "✅ Full cleanup complete (volumes removed)"
else
    echo "✅ Containers stopped (volumes preserved)"
    echo "   Use '--full' to remove volumes"
fi

echo "=============================="