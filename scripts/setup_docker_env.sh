#!/bin/bash
set -e

echo "=============================="
echo "🚀 CDW-PepsiCo Docker Environment Setup"
echo "=============================="

# Update system packages
echo "📦 Updating system packages..."
sudo apt update -y
sudo apt upgrade -y

# Install dependencies
echo "🔧 Installing required packages..."
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg \
    lsb-release

# Add Docker GPG key and repo
echo "📥 Adding Docker repository..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
echo "🐳 Installing Docker..."
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Enable and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Check Docker version
docker --version

# Install Docker Compose v2 (as the docker compose subcommand)
if ! docker compose version &>/dev/null; then
    echo "📦 Installing Docker Compose v2..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose installed:"
    docker-compose --version
else
    echo "✅ Docker Compose plugin already available"
fi

# Optional: Add current user to docker group to avoid sudo
sudo usermod -aG docker $USER
echo "✅ Docker environment setup complete!"
echo "⚠️ You may need to log out and back in for Docker group changes to take effect."
