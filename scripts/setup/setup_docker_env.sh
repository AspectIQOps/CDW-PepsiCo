#!/bin/bash
# ==========================================================
# 🚀 CDW-PepsiCo Docker Environment Setup
# Sets up Docker and Docker Compose plugin on Ubuntu.
# Must be run with sudo/root
# ==========================================================

set -euo pipefail

echo "=============================="
echo "🚀 Setting up Docker Environment"
echo "=============================="

# --- Root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script with sudo or as root."
  echo "   Usage: sudo ./scripts/setup/setup_docker_env.sh"
  exit 1
fi

# --- Package setup ---
echo "📦 Updating packages..."
apt-get update -y && apt-get upgrade -y

echo "🔧 Installing prerequisites..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg \
    lsb-release \
    postgresql-client

# --- Docker repo and install ---
if [ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
  echo "📥 Adding Docker GPG key and repository..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
fi

echo "🐳 Installing Docker and Compose plugin..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl restart docker

echo ""
echo "✅ Docker installed:"
docker --version
docker compose version
echo ""

# --- Add user to docker group (safe if already added) ---
CALLING_USER="${SUDO_USER:-$(whoami)}"
if [ "$CALLING_USER" != "root" ]; then
    if id -nG "$CALLING_USER" | grep -qw docker; then
      echo "✅ User '$CALLING_USER' already in docker group"
    else
      usermod -aG docker "$CALLING_USER"
      echo "✅ Added '$CALLING_USER' to docker group"
      echo "⚠️  IMPORTANT: Log out and back in for docker group changes to take effect"
    fi
else
    echo "⚠️  Running as root - skipping docker group setup"
fi

# --- Install Python dependencies for local development ---
echo ""
read -p "📦 Install Python dependencies for local development? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing Python and pip..."
    apt-get install -y python3 python3-pip python3-venv
    echo "✅ Python installed:"
    python3 --version
    pip3 --version
fi

# --- Install AWS CLI ---
echo ""
read -p "☁️  Install AWS CLI for SSM integration? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v aws &> /dev/null; then
        echo "✅ AWS CLI already installed:"
        aws --version
    else
        echo "Installing AWS CLI..."
        apt-get install -y unzip
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        ./aws/install
        rm -rf aws awscliv2.zip
        echo "✅ AWS CLI installed:"
        aws --version
    fi
fi

echo ""
echo "=============================================="
echo "✅ Docker environment setup complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Log out and back in (if docker group was added)"
echo "  2. Clone/navigate to your project repository"
echo "  3. Create .env file with your configuration"
echo "  4. Run: ./scripts/setup/setup_docker_stack.sh"
echo ""