#!/bin/bash
set -e

echo "=============================="
echo "🔍 CDW-PepsiCo Post-Install Check"
echo "=============================="

# Kernel check
KERNEL=$(uname -r)
echo "✅ Kernel version: $KERNEL"

# Docker check
if ! command -v docker &>/dev/null; then
    echo "❌ Docker is not installed."
    exit 1
fi
DOCKER_VER=$(docker --version)
echo "✅ Docker installed: $DOCKER_VER"

# Docker Compose check
if ! docker compose version &>/dev/null; then
    echo "❌ Docker Compose is not installed."
    exit 1
fi
COMPOSE_VER=$(docker compose version)
echo "✅ Docker Compose installed: $COMPOSE_VER"

# Docker service running
if ! systemctl is-active --quiet docker; then
    echo "❌ Docker service is not running."
    exit 1
fi
echo "✅ Docker service is running."

# Running containers
echo ""
echo "📦 Currently running Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Local Docker images
echo ""
echo "🖼️ Docker images available locally:"
docker images

echo ""
echo "✅ Post-install checks complete!"
