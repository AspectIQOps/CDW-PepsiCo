#!/bin/bash
set -e

echo "=============================="
echo "🚀 CDW-PepsiCo Docker Stack Setup"
echo "=============================="

# Ensure scripts and entrypoints are executable
echo "🔧 Setting executable permissions for scripts..."
chmod +x scripts/*.py
chmod +x docker/etl/entrypoint.sh

# Check .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found in repo root! Please create it before continuing."
    exit 1
fi

# Run post-install check
./scripts/post_install_check.sh

read -p "Press Enter to continue with Docker stack setup, or Ctrl+C to cancel..."

echo "🐳 Starting Docker stack..."
docker compose -f docker/docker-compose.yaml up --build -d
