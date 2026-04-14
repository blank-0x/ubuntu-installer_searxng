#!/bin/bash

set -euo pipefail

LOG_FILE="/var/log/searxng-installer.log"
PORT=8080
INSTALL_DOCKER=true

# -----------------------------
# Logging
# -----------------------------
log() {
    echo "[+] $1"
    echo "[+] $1" >> "$LOG_FILE"
}

error() {
    echo "[ERROR] $1" >&2
    echo "[ERROR] $1" >> "$LOG_FILE"
    exit 1
}

# -----------------------------
# Argument parsing
# -----------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --no-docker-install)
            INSTALL_DOCKER=false
            shift
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

# -----------------------------
# Checks
# -----------------------------
if [[ "$EUID" -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

if ! grep -qi ubuntu /etc/os-release; then
    error "This script only supports Ubuntu"
fi

# -----------------------------
# System update
# -----------------------------
log "Updating system..."
apt update -y && apt upgrade -y

# -----------------------------
# Install dependencies
# -----------------------------
log "Installing dependencies..."
apt install -y ca-certificates curl gnupg lsb-release

# -----------------------------
# Install Docker (optional)
# -----------------------------
if [ "$INSTALL_DOCKER" = true ]; then
    log "Installing Docker..."

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list

    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log "Adding user to docker group..."
    usermod -aG docker "$SUDO_USER"
else
    log "Skipping Docker installation"
fi

# -----------------------------
# Setup SearXNG
# -----------------------------
log "Creating installation directory..."
mkdir -p /opt/searxng/core-config
cd /opt/searxng

log "Downloading configuration..."
curl -fsSL -O https://raw.githubusercontent.com/searxng/searxng/master/container/docker-compose.yml
curl -fsSL -O https://raw.githubusercontent.com/searxng/searxng/master/container/.env.example

cp .env.example .env

# Set custom port
log "Configuring port: $PORT"
sed -i "s/8080:8080/${PORT}:8080/g" docker-compose.yml

# Generate random SECRET_KEY
SECRET_KEY=$(openssl rand -hex 32)
sed -i "s|SECRET_KEY=.*|SECRET_KEY=$SECRET_KEY|g" .env || echo "SECRET_KEY=$SECRET_KEY" >> .env

# -----------------------------
# Deploy
# -----------------------------
log "Starting SearXNG..."
docker compose up -d

# -----------------------------
# Final output
# -----------------------------
log "Installation completed"

echo ""
echo "======================================"
echo "SearXNG installed successfully"
echo "Access: http://localhost:$PORT"
echo ""
echo "Next steps:"
echo "- Run: newgrp docker  (or re-login)"
echo "- Config: /opt/searxng/.env"
echo "- Logs: $LOG_FILE"
echo "======================================"
