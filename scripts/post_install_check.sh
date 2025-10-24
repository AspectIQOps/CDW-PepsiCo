#!/bin/bash
set -e

echo "=============================="
echo "🔍 CDW-PepsiCo Post-Install Check"
echo "=============================="

# --- 1️⃣ Check kernel version ---
EXPECTED_KERNEL="6.14.0-1015-aws"
CURRENT_KERNEL=$(uname -r)

REBOOT_REQUIRED=false
if [ "$CURRENT_KERNEL" != "$EXPECTED_KERNEL" ]; then
    echo "⚠️ Warning: Kernel version mismatch."
    echo "   Current kernel: $CURRENT_KERNEL"
    echo "   Expected kernel: $EXPECTED_KERNEL"
    echo "   A reboot is recommended to load the new kernel."
    REBOOT_REQUIRED=true
else
    echo "✅ Kernel version matches expected."
fi

# --- 2️⃣ Check Docker installation ---
if ! command -v docker &>/dev/null; then
    echo "❌ Docker is not installed or not in PATH."
    exit 1
else
    echo "✅ Docker installed: $(docker --version)"
fi

# --- 3️⃣ Check Docker Compose installation ---
if docker compose version &>/dev/null; then
    echo "✅ Docker Compose (v2 plugin) installed: $(docker compose version)"
elif command -v docker-compose &>/dev/null; then
    echo "✅ Docker Compose (legacy) installed: $(docker-compose --version)"
else
    echo "❌ Docker Compose not found!"
    exit 1
fi

# --- 4️⃣ Check if Docker service is running ---
if systemctl is-active --quiet docker; then
    echo "✅ Docker service is running."
else
    echo "❌ Docker service is not running!"
    echo "   Start it with: sudo systemctl start docker"
fi

# --- 5️⃣ Optional: List running containers ---
echo ""
echo "📦 Currently running Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# --- 6️⃣ Optional: List Docker images ---
echo ""
echo "🖼️ Docker images available locally:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

echo ""
echo "✅ Post-install checks complete!"

# --- 7️⃣ Prompt for reboot if needed ---
if [ "$REBOOT_REQUIRED" = true ]; then
    echo ""
    read -p "⚠️ Kernel mismatch detected. Would you like to reboot now? (y/N): " REBOOT_CONFIRM
    case "$REBOOT_CONFIRM" in
        [yY][eE][sS]|[yY])
            echo "🔄 Rebooting system..."
            sudo reboot
            ;;
        *)
            echo "⚠️ Reboot skipped. Kernel changes will not take effect until next reboot."
            ;;
    esac
fi
