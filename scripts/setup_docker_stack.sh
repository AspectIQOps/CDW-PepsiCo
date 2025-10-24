#!/bin/bash
set -e

echo "=============================="
echo "🚀 CDW-PepsiCo Docker Stack Setup"
echo "=============================="

# --- 1️⃣ Check for .env in repo root ---
if [ ! -f ../.env ]; then
    echo "❌ .env file not found in repo root! Please create it before continuing."
    exit 1
fi

# --- 2️⃣ Make scripts executable ---
chmod +x ../scripts/*.sh

# --- 3️⃣ Run post-install checks (with reboot prompt) ---
echo "🔍 Running post-install diagnostics..."
sudo ../scripts/post_install_check.sh

# --- 4️⃣ Confirm user wants to continue after potential reboot ---
read -p "Press Enter to continue with Docker stack setup, or Ctrl+C to cancel..."

# --- 5️⃣ Start Docker stack with .env from repo root ---
echo "🐳 Starting Docker stack..."
docker compose --env-file ../.env -f docker/docker-compose.yaml up -d

echo "✅ Docker stack started successfully!"

# --- 6️⃣ Show running containers ---
docker compose --env-file ../.env -f docker/docker-compose.yaml ps

# --- 7️⃣ Final reminder if kernel still mismatched ---
EXPECTED_KERNEL="6.14.0-1015-aws"
CURRENT_KERNEL=$(uname -r)
if [ "$CURRENT_KERNEL" != "$EXPECTED_KERNEL" ]; then
    echo ""
    echo "⚠️ Kernel version still does not match expected: $EXPECTED_KERNEL"
    echo "   Docker stack is running, but a system reboot is recommended."
fi
