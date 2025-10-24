#!/usr/bin/env bash
set -e

echo "----------------------------------------"
echo " Starting Docker ETL stack setup"
echo "----------------------------------------"

# Variables
REPO_DIR="$HOME/CDW-PepsiCo"
BRANCH="main"    # You can override this at runtime: ./setup_docker_stack.sh feature_branch
CHECK_SCRIPT="./docker/docker_install_check.sh"

# Allow overriding the branch as an argument
if [ "$1" ]; then
  BRANCH="$1"
fi

# 1️⃣ Update and install base dependencies
echo "Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y

echo "Installing dependencies..."
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git

# 2️⃣ Install Docker if not present
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  sudo systemctl enable docker
  sudo systemctl start docker
  echo "✅ Docker installed and running."
else
  echo "✅ Docker already installed."
fi

# 3️⃣ Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null; then
  echo "Installing Docker Compose..."
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  echo "✅ Docker Compose installed."
else
  echo "✅ Docker Compose already installed."
fi

# 4️⃣ Clone the repo (if not already present)
if [ ! -d "$REPO_DIR" ]; then
  echo "Cloning repository..."
  git clone https://github.com/YOUR_ORG/CDW-PepsiCo.git "$REPO_DIR"
else
  echo "✅ Repo already exists at $REPO_DIR"
fi

cd "$REPO_DIR"
git fetch origin
git checkout "$BRANCH"
echo "✅ Checked out branch: $BRANCH"

# 5️⃣ Build and start containers
if [ -f docker/docker-compose.yml ]; then
  echo "Starting Docker Compose stack..."
  cd docker
  sudo docker-compose up -d --build
  echo "✅ Containers built and started."
else
  echo "❌ docker-compose.yml not found in ./docker directory!"
  exit 1
fi

# 6️⃣ Run post-install validation script
if [ -f "$CHECK_SCRIPT" ]; then
  echo "Running post-install validation..."
  bash "$CHECK_SCRIPT"
else
  echo "⚠️ Validation script not found at $CHECK_SCRIPT"
fi

echo "----------------------------------------"
echo "✅ Docker ETL stack setup complete."
echo "----------------------------------------"
