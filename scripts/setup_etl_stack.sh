#!/bin/bash
set -e

echo "🚀 Starting ETL stack setup..."

# --- 0. Ensure we are in the repo root ---
cd "$(dirname "$0")"
if [ ! -f ".env" ] && [ -f "../.env" ]; then
  cd ..
fi

# --- 1. Check for .env file ---
if [ ! -f ".env" ]; then
  echo "⚠️  No .env file found!"
  if [ -f ".env.example" ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
    echo "✅ .env file created from template."
    echo "👉 Please edit the .env file with your credentials, then re-run this script."
    exit 1
  else
    echo "❌ No .env or .env.example file found. Exiting."
    exit 1
  fi
fi

# --- 2. Update OS and install required packages ---
echo "📦 Updating system and installing dependencies..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y git python3 python3-venv python3-pip \
                    postgresql postgresql-contrib \
                    docker.io docker-compose curl unzip

# --- 3. Enable and start services ---
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl enable postgresql
sudo systemctl start postgresql

# --- 4. Clone repo if missing ---
if [ ! -d "CDW-PepsiCo" ]; then
  echo "📁 Cloning repo..."
  git clone https://github.com/AspectIQOps/CDW-PepsiCo.git
  cd CDW-PepsiCo
fi

# --- 5. Initialize PostgreSQL ---
echo "🗃️  Setting up PostgreSQL
