#!/bin/bash
# ==========================================================
# 🚀 CDW-PepsiCo Docker Environment Setup
# Sets up Docker and Docker Compose plugin on Ubuntu.
# ==========================================================

set -euo pipefail

echo "=============================="
echo "🚀 Setting up Docker Environment"
echo "=============================="

# --- Root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script with sudo or as root."
  exit 1
fi

# --- Package setup ---
echo "📦 Updating packages..."
apt-get update -y && apt-get upgrade -y

echo "🔧 Installing prerequisites..."
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

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

docker --version
docker compose version

# --- Add user to docker group (safe if already added) ---
CALLING_USER="${SUDO_USER:-$(whoami)}"
if id -nG "$CALLING_USER" | grep -qw docker; then
  echo "✅ User '$CALLING_USER' already in docker group"
else
  usermod -aG docker "$CALLING_USER"
  echo "✅ Added '$CALLING_USER' to docker group (re-login required)"
fi

echo "✅ Docker environment setup complete!"
echo "⚠️ Log out and back in for docker group changes to take effect."
