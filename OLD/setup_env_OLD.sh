#!/bin/bash
set -e

# --- Detect paths dynamically ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="/opt/appd-licensing"
POSTGRES_USER="postgres"

echo "🔄 Updating system packages..."
sudo apt update && sudo apt -y upgrade

echo "🐍 Installing Python, PostgreSQL, and required tools..."
sudo apt -y install python3 python3-venv python3-pip postgresql postgresql-contrib wget curl unzip software-properties-common

# --- Ensure PostgreSQL service is enabled and running ---
echo "🗄️ Enabling and starting PostgreSQL service..."
sudo systemctl daemon-reload
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to accept connections..."
sleep 5
until sudo -u $POSTGRES_USER psql -c '\l' >/dev/null 2>&1; do
    sleep 2
done
echo "✅ PostgreSQL is running."

# --- Create base directories ---
echo "📂 Setting up project directories..."
sudo mkdir -p "$BASE_DIR"
sudo chown -R "$SUDO_USER":"$SUDO_USER" "$BASE_DIR"

# --- Setup Python virtual environment ---
echo "🐍 Creating Python virtual environment..."
python3 -m venv "$BASE_DIR/etl_env"
source "$BASE_DIR/etl_env/bin/activate"
pip install --upgrade pip
pip install requests pandas psycopg2-binary python-dotenv

# --- Install Grafana ---
echo "🔧 Installing Grafana..."
if ! dpkg -s grafana >/dev/null 2>&1; then
    sudo add-apt-repository -y "deb https://packages.grafana.com/oss/deb stable main"
    wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
    sudo apt update
    sudo apt -y install grafana
fi

echo "🔹 Enabling and starting Grafana..."
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "✅ Environment setup complete!"
echo "Activate Python venv: source $BASE_DIR/etl_env/bin/activate"
