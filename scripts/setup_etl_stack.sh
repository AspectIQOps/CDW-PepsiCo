#!/bin/bash
set -e

echo "🚀 Starting ETL stack setup..."

# --- 1. Update OS and install required packages ---
echo "📦 Updating system and installing dependencies..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y git python3 python3-venv python3-pip \
                    postgresql postgresql-contrib \
                    docker.io docker-compose curl unzip

# --- 2. Enable and start PostgreSQL ---
echo "🗃️ Setting up PostgreSQL service..."
sudo systemctl enable postgresql
sudo systemctl start postgresql

# --- 3. Set up PostgreSQL database and user ---
echo "🗄️ Creating database and roles..."
sudo -i -u postgres psql <<EOF
CREATE DATABASE appd_licensing;
CREATE ROLE appd_ro WITH LOGIN PASSWORD 'ChangeMe123!';
GRANT CONNECT ON DATABASE appd_licensing TO appd_ro;
EOF

# --- 4. Initialize DB schema ---
if [ -f ~/CDW-PepsiCo/postgres/init.sql ]; then
    echo "⚡ Initializing database schema..."
    sudo -i -u postgres psql -d appd_licensing -f ~/CDW-PepsiCo/postgres/init.sql
else
    echo "⚠️  No init.sql found — skipping database initialization."
fi

# --- 5. Grant full privileges to ETL user ---
sudo -i -u postgres psql -d appd_licensing <<EOF
GRANT USAGE ON SCHEMA public TO appd_ro;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appd_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appd_ro;
EOF

# --- 6. Setup Python environment ---
echo "🐍 Setting up Python environment..."
python3 -m venv ~/etl_env
source ~/etl_env/bin/activate
pip install --upgrade pip
if [ -f ~/CDW-PepsiCo/requirements.txt ]; then
    pip install -r ~/CDW-PepsiCo/requirements.txt
else
    echo "⚠️  requirements.txt not found — skipping Python dependency installation."
fi

# --- 7. Install Grafana ---
echo "📊 Installing Grafana..."
sudo apt install -y apt-transport-https software-properties-common
sudo curl -fsSL https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y grafana

# --- 8. Enable and start Grafana service ---
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# --- 9. Install Grafana plugins ---
echo "🔌 Installing Grafana plugins..."
sudo grafana-cli plugins install grafana-piechart-panel
sudo grafana-cli plugins install grafana-worldmap-panel
sudo grafana-cli plugins install grafana-clock-panel
sudo systemctl restart grafana-server

# --- 10. Completion ---
echo "✅ ETL stack setup complete!"
echo "PostgreSQL DB: appd_licensing"
echo "Grafana is running on port 3000"
echo "Activate Python environment: source ~/etl_env/bin/activate"
