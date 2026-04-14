# SearXNG One-Click Installer (Ubuntu)

Automated installation script to deploy SearXNG using Docker on Ubuntu systems.

## Overview

This project provides a reproducible installation method for SearXNG using containerization. It avoids common issues found in the upstream installer, especially on non-standard distributions.

The script performs the following:

- Installs Docker from the official repository
- Configures Docker service and permissions
- Downloads SearXNG container configuration
- Deploys the service using Docker Compose

## Installation

### 1. Clone the repository

git clone https://github.com/yourusername/searxng-installer.git  
cd searxng-installer

### 2. Make the script executable

chmod +x install_searxng.sh

### 3. Run the installer

sudo ./install_searxng.sh

## Post-installation

Apply Docker group permissions:

newgrp docker

Alternatively, log out and start a new session.

## Access

Default endpoint:

http://localhost:8080

## Service Management

Working directory:

cd /opt/searxng

Start:

docker compose up -d

Stop:

docker compose down

Status:

docker ps

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04
- sudo privileges
- Internet access

## Rationale

The official SearXNG installer does not support all distributions and may fail in environments such as Kali Linux due to:

- Distribution-specific assumptions
- Python packaging restrictions (PEP 668)
- Missing service integrations

This project uses Docker to provide a consistent and isolated runtime environment.

## Production Considerations

For non-local deployments:

- Set a custom SECRET_KEY in .env
- Use a reverse proxy such as NGINX with TLS
- Restrict access via firewall or authentication

## About

SearXNG is a privacy-focused metasearch engine that aggregates results from multiple sources without tracking users.

## License

MIT
