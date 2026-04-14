#!/bin/bash
# =============================================================================
# SearXNG One-Click Installer (Ubuntu)
# Deploys SearXNG via Docker on Ubuntu 20.04 / 22.04 / 24.04
# Usage: sudo ./install_searxng.sh [--port PORT] [--no-docker-install] [--help]
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration defaults
# -----------------------------------------------------------------------------
readonly LOG_FILE="/var/log/searxng-installer.log"
readonly INSTALL_DIR="/opt/searxng"
readonly COMPOSE_URL="https://raw.githubusercontent.com/searxng/searxng/master/container/docker-compose.yml"
readonly ENV_URL="https://raw.githubusercontent.com/searxng/searxng/master/container/.env.example"

PORT=8080
INSTALL_DOCKER=true

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log()  { echo "[+] $1" | tee -a "$LOG_FILE"; }
warn() { echo "[!] $1" | tee -a "$LOG_FILE"; }

error() {
    echo "[ERROR] $1" | tee -a "$LOG_FILE" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Options:
  --port PORT           Port to expose SearXNG on (default: 8080, range: 1-65535)
  --no-docker-install   Skip Docker installation (use if Docker is already installed)
  --help                Show this help message

Examples:
  sudo $0
  sudo $0 --port 9090
  sudo $0 --port 9090 --no-docker-install
EOF
    exit 0
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            [[ -n "${2:-}" ]] || error "--port requires a value"
            PORT="$2"
            shift 2
            ;;
        --no-docker-install)
            INSTALL_DOCKER=false
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            error "Unknown argument: $1. Run with --help for usage."
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Validations
# -----------------------------------------------------------------------------
validate() {
    # Root check
    [[ "$EUID" -eq 0 ]] || error "This script must be run as root. Use: sudo $0"

    # Ubuntu check
    grep -qi ubuntu /etc/os-release || error "This script only supports Ubuntu (20.04 / 22.04 / 24.04)"

    # Port validation
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 || "$PORT" -gt 65535 ]]; then
        error "Invalid port: '$PORT'. Must be an integer between 1 and 65535."
    fi

    # Check for required tools
    for cmd in curl openssl; do
        command -v "$cmd" &>/dev/null || error "Required tool not found: $cmd"
    done

    # Resolve SUDO_USER safely
    if [[ -z "${SUDO_USER:-}" ]]; then
        warn "SUDO_USER is not set. Docker group assignment will be skipped."
        warn "Add yourself to the docker group manually: usermod -aG docker \$USER"
    fi
}

# -----------------------------------------------------------------------------
# Init log file
# -----------------------------------------------------------------------------
init_log() {
    touch "$LOG_FILE" 2>/dev/null || {
        LOG_FILE="/tmp/searxng-installer.log"
        warn "Cannot write to /var/log. Logging to $LOG_FILE instead."
        touch "$LOG_FILE"
    }
    log "============================================================"
    log "SearXNG Installer started at $(date)"
    log "Port: $PORT | Docker install: $INSTALL_DOCKER"
    log "============================================================"
}

# -----------------------------------------------------------------------------
# System update and dependencies
# -----------------------------------------------------------------------------
install_dependencies() {
    log "Updating package lists..."
    apt-get update -y

    log "Installing required packages..."
    apt-get install -y ca-certificates curl gnupg lsb-release
}

# -----------------------------------------------------------------------------
# Docker installation
# -----------------------------------------------------------------------------
install_docker() {
    if command -v docker &>/dev/null; then
        log "Docker is already installed ($(docker --version)). Skipping installation."
        return
    fi

    log "Installing Docker..."

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log "Docker installed: $(docker --version)"

    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER"
        log "User '$SUDO_USER' added to the docker group."
    fi
}

# -----------------------------------------------------------------------------
# Deploy SearXNG
# -----------------------------------------------------------------------------
deploy_searxng() {
    log "Setting up installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/core-config"
    cd "$INSTALL_DIR"

    log "Downloading docker-compose.yml..."
    curl -fsSL -o docker-compose.yml "$COMPOSE_URL" \
        || error "Failed to download docker-compose.yml. Check your internet connection."

    log "Downloading .env.example..."
    curl -fsSL -o .env.example "$ENV_URL" \
        || error "Failed to download .env.example."

    # Only overwrite .env if it doesn't already exist
    if [[ ! -f .env ]]; then
        cp .env.example .env
        log ".env file created from template."
    else
        warn ".env already exists. Skipping overwrite to preserve existing config."
    fi

    # Set custom port by replacing the port mapping line
    if [[ "$PORT" -ne 8080 ]]; then
        log "Setting port to $PORT..."
        sed -i "s|\"8080:8080\"|\"${PORT}:8080\"|g; s|'8080:8080'|'${PORT}:8080'|g; s|- 8080:8080|- ${PORT}:8080|g" docker-compose.yml
    fi

    # Generate and inject SECRET_KEY
    local secret_key
    secret_key=$(openssl rand -hex 32)

    if grep -q "SECRET_KEY" .env; then
        sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${secret_key}|" .env
        log "SECRET_KEY updated in .env."
    else
        echo "SECRET_KEY=${secret_key}" >> .env
        log "SECRET_KEY appended to .env."
    fi

    log "Pulling images and starting SearXNG..."
    docker compose pull
    docker compose up -d

    log "SearXNG deployment complete."
}

# -----------------------------------------------------------------------------
# Health check
# -----------------------------------------------------------------------------
health_check() {
    log "Waiting for SearXNG to become available..."
    local retries=10
    local wait=3

    for ((i = 1; i <= retries; i++)); do
        if curl -fsSL --max-time 5 "http://localhost:${PORT}" &>/dev/null; then
            log "SearXNG is up and responding on port $PORT."
            return 0
        fi
        sleep "$wait"
        log "Attempt $i/$retries failed. Retrying in ${wait}s..."
    done

    warn "Health check did not succeed. SearXNG may still be starting."
    warn "Check status with: docker compose -C $INSTALL_DIR ps"
    return 0
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "========================================================"
    echo "  SearXNG installed successfully"
    echo "========================================================"
    echo "  URL:     http://localhost:$PORT"
    echo "  Dir:     $INSTALL_DIR"
    echo "  Config:  $INSTALL_DIR/.env"
    echo "  Logs:    $LOG_FILE"
    echo ""
    echo "  Service management:"
    echo "    docker compose -C $INSTALL_DIR up -d"
    echo "    docker compose -C $INSTALL_DIR down"
    echo "    docker compose -C $INSTALL_DIR ps"
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo ""
        echo "  Apply Docker group (run as $SUDO_USER):"
        echo "    newgrp docker   # or log out and back in"
    fi
    echo "========================================================"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    init_log
    validate

    log "--- Phase 1: System dependencies ---"
    install_dependencies

    log "--- Phase 2: Docker ---"
    if [[ "$INSTALL_DOCKER" == true ]]; then
        install_docker
    else
        log "Skipping Docker installation (--no-docker-install)"
        command -v docker &>/dev/null || error "Docker not found. Remove --no-docker-install or install Docker manually."
    fi

    log "--- Phase 3: SearXNG deployment ---"
    deploy_searxng

    log "--- Phase 4: Health check ---"
    health_check

    log "--- Done ---"
    print_summary
}

main
