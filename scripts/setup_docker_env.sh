#!/bin/bash
# setup_docker_env.sh
# Automated environment setup for CDW-PepsiCo Docker stack

set -e

echo "=============================="
echo "🚀 CDW-PepsiCo Docker Setup"
echo "=============================="

# --- Update system ---
echo "📦 Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# --- Install dependencies ---
echo "🐳 Installing Docker and Docker Compose..."
sudo apt install -y docker.io docker-compose-plugin git

# Enable Docker
sudo systemctl enable docker
sudo systemctl start docker

# --- Verify installation ---
echo "✅ Docker version:"
docker --version
echo "✅ Docker Compose version:"
docker compose version

# --- Clone repo if not already present ---
REPO_DIR="CDW-PepsiCo"
if [ ! -d "$REPO_DIR" ]; then
  echo "📁 Cloning CDW-PepsiCo repository..."
  git clone https://github.com/AspectIQOps/CDW-PepsiCo.git
else
  echo "📁 Repository already exists. Skipping clone."
fi

cd "$REPO_DIR"

# --- Checkout dockerization branch ---
echo "🌿 Checking out dockerization branch..."
git fetch origin
git checkout dockerization || echo "⚠️ Branch already active or checkout failed."

# --- Copy .env.example if .env doesn’t exist ---
if [ ! -f ".env" ]; then
  echo "🧩 Creating .env file..."
  if [ -f ".env.example" ]; then
    cp .env.example .env
  else
    touch .env
  fi
else
  echo "🧩 .env file already exists."
fi

# --- Display .env info ---
echo
echo "📋 Please verify your .env file values before continuing:"
echo "--------------------------------------------------------"
echo "DB_USER=postgres"
echo "DB_PASSWORD=supersecret"
echo "DB_NAME=cdw"
echo "SN_INSTANCE=myinstance"
echo "SN_USER=apiuser"
echo "SN_PASS=apipassword"
echo "--------------------------------------------------------"
echo
read -p "Press ENTER to continue with Docker build and launch..."

# --- Build and start Docker containers ---
echo "⚙️ Building Docker images..."
sudo docker compose build

echo "🚀 Starting Docker stack..."
sudo docker compose up -d

# --- Show status ---
echo "✅ Docker containers running:"
sudo docker compose ps

echo
echo "🌐 Grafana available at: http://<your-ec2-public-dns>:3000"
echo "   Username: admin | Password: admin"
echo
echo "✅ Setup complete!"
