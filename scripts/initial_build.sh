#!/bin/bash
set -e

# --- Determine script directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="/opt/appd-licensing"
POSTGRES_USER="postgres"

echo "🚀 Starting full initial build..."

# --- 1️⃣ Setup environment ---
SETUP_SCRIPT="$SCRIPT_DIR/setup_env.sh"
if [[ -f "$SETUP_SCRIPT" ]]; then
    echo "1️⃣ Running setup_env.sh..."
    sudo bash "$SETUP_SCRIPT"
else
    echo "❌ setup_env.sh not found at $SETUP_SCRIPT. Cannot continue."
    exit 1
fi

# --- 2️⃣ Post-install check ---
POST_CHECK="$SCRIPT_DIR/post_install_check.sh"
if [[ -f "$POST_CHECK" ]]; then
    echo "2️⃣ Running post-install checks..."
    bash "$POST_CHECK"
else
    echo "⚠️ post_install_check.sh not found. Skipping."
fi

echo "🎉 Initial build complete!"
