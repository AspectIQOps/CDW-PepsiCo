#!/bin/bash
# ==========================================================
# EC2 Initial Setup Script
# Run ONCE on a fresh EC2 Ubuntu instance
# Must be run with sudo
# ==========================================================

set -euo pipefail

echo "=========================================="
echo "🚀 EC2 Initial Setup for PepsiCo ETL"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run with sudo: sudo ./scripts/setup/ec2_initial_setup.sh"
    exit 1
fi

# Get the actual user (not root)
ACTUAL_USER="${SUDO_USER:-ubuntu}"

echo "📦 Updating system packages..."
apt-get update -y && apt-get upgrade -y

echo "🔧 Installing prerequisites..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg \
    lsb-release \
    postgresql-client \
    netcat-openbsd

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker..."
    
    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    echo "✅ Docker installed: $(docker --version)"
else
    echo "✅ Docker already installed: $(docker --version)"
fi

# Add user to docker group
if id -nG "$ACTUAL_USER" | grep -qw docker; then
    echo "✅ User '$ACTUAL_USER' already in docker group"
else
    usermod -aG docker "$ACTUAL_USER"
    echo "✅ Added '$ACTUAL_USER' to docker group"
fi

# Install AWS CLI
if ! command -v aws &> /dev/null; then
    echo "☁️  Installing AWS CLI..."
    apt-get install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
    echo "✅ AWS CLI installed: $(aws --version)"
else
    echo "✅ AWS CLI already installed: $(aws --version)"
fi

# Configure AWS region
echo "🌍 Configuring AWS region..."
su - "$ACTUAL_USER" -c "aws configure set default.region us-east-2"

# Install Python packages (optional)
echo "🐍 Installing Python packages..."
apt-get install -y python3 python3-pip python3-venv

echo ""
echo "=========================================="
echo "✅ EC2 Initial Setup Complete!"
echo "=========================================="
echo ""
echo "⚠️  IMPORTANT: Log out and back in for docker group to take effect"
echo ""
echo "Next steps:"
echo "  1. Exit current session: exit"
echo "  2. SSH back in"
echo "  3. Run: cd ~/CDW-PepsiCo"
echo "  4. Run: ./scripts/setup/daily_startup.sh"
echo ""
echo "=========================================="
