#!/bin/bash
# Daily Startup - Complete Environment Setup

set -e

echo "=========================================="
echo "🚀 Daily Environment Startup"
echo "=========================================="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Pull latest code
echo "📥 Pulling latest code from repository..."
git pull origin deploy-docker 2>/dev/null || {
    echo "⚠️  Git pull failed or no changes - using local code"
}

# Run health check
echo ""
echo "🏥 Running system health check..."
./scripts/utils/health_check.sh

# Initialize database schema
echo ""
echo "🗄️  Initializing database schema and seed data..."
./scripts/setup/sql_initialization.sh

# Build and run ETL pipeline
echo ""
echo "⚙️  Building and running ETL pipeline..."
docker compose -f docker-compose.ec2.yaml up --build

# Verify setup
echo ""
echo "✅ Running final verification..."
./scripts/utils/verify_setup.sh

echo ""
echo "=========================================="
echo "🎉 Daily startup complete!"
echo ""
echo "Next steps:"
echo "  • Access Grafana to view dashboards"
echo "  • Run validation: python3 scripts/utils/validate_pipeline.py"
echo "  • Check logs: docker logs pepsico-etl-analytics"
echo ""
echo "=========================================="