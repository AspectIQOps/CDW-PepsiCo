#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="/opt/appd-licensing"
POSTGRES_USER="postgres"

echo "🚀 Starting full initial build..."

# --- 1️⃣ Setup environment ---
echo "1️⃣ Running setup_env.sh..."
"$SCRIPT_DIR/setup_env.sh"

# --- 2️⃣ Create DB schema ---
CREATE_SQL="$BASE_DIR/postgres/create_tables.sql"
if [[ -f "$CREATE_SQL" ]]; then
    echo "2️⃣ Creating database schema..."
    sudo -u $POSTGRES_USER psql -f "$CREATE_SQL"
    echo "✅ Database schema created."
else
    echo "⚠️ create_tables.sql not found at $CREATE_SQL. Skipping."
fi

# --- 3️⃣ Seed initial data ---
SEED_SQL="$BASE_DIR/postgres/seed_all_tables.sql"
if [[ -f "$SEED_SQL" ]]; then
    echo "3️⃣ Seeding database..."
    sudo -u $POSTGRES_USER psql -f "$SEED_SQL"
    echo "✅ Seed data inserted."
else
    echo "⚠️ seed_all_tables.sql not found at $SEED_SQL. Skipping."
fi

# --- 4️⃣ Post-install check ---
POST_CHECK="$SCRIPT_DIR/post_install_check.sh"
if [[ -f "$POST_CHECK" ]]; then
    echo "4️⃣ Running post-install checks..."
    sudo "$POST_CHECK"
else
    echo "⚠️ post_install_check.sh not found. Skipping."
fi

echo "🎉 Initial build complete!"
