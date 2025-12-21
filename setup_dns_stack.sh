#!/bin/bash
set -e

# ==============================================================================
# Rootless Podman DNS Stack Setup Script
# ==============================================================================
# usage: ./setup_dns_stack.sh
# description: Replicates the stack by copying files from the local 'containers' directory.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Starting DNS Stack Deployment...${NC}"

# --- 1. Validation Checks ---

# Check 1: Podman installed?
if ! command -v podman &> /dev/null; then
    echo -e "${RED}[ERROR] Podman is not installed.${NC} Please run: sudo dnf install podman"
    exit 1
fi

# Check 2: Project Structure exists?
if [ ! -d "./containers" ]; then
    echo -e "${RED}[ERROR] Project directory './containers' not found.${NC}"
    echo "Please run this script from the root of the project repository."
    exit 1
fi

# Check 3: Secrets exist?
if ! podman secret exists ftp_secret; then
    echo -e "${RED}[ERROR] Secret 'ftp_secret' is missing.${NC}"
    echo -e "Create it with: ${YELLOW}printf 'YOUR_PASSWORD' | podman secret create ftp_secret -${NC}"
    exit 1
fi

if ! podman secret exists my_secret; then
    echo -e "${RED}[ERROR] Secret 'my_secret' is missing.${NC}"
    echo -e "Create it with: ${YELLOW}printf 'YOUR_PASSWORD' | podman secret create my_secret -${NC}"
    exit 1
fi

if ! podman secret exists duckdns_api_token; then
    echo -e "${YELLOW}[WARN] Secret 'duckdns_api_token' is missing.${NC} (Ignore if not using DuckDNS)"
fi

# --- 2. Directory Creation ---
echo -e "${GREEN}[+] Creating host directories...${NC}"
mkdir -p ~/.config/containers/systemd/
mkdir -p ~/.config/containers/storage/pihole/{etc-pihole,etc-dnsmasq.d,logs}
mkdir -p ~/.config/containers/storage/unbound
mkdir -p ~/.config/containers/storage/caddy/{caddy-config,caddy-data,Caddyfile_dir}

# --- 3. File Installation ---
echo -e "${GREEN}[+] installing configuration files...${NC}"

# Function to copy with backup
install_file() {
    local src="$1"
    local dest="$2"

    if [ ! -f "$src" ]; then
        echo -e "${RED}[ERROR] Missing source file: $src${NC}"
        exit 1
    fi

    # Simple backup if dest exists and is different
    if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
        cp "$dest" "${dest}.bak"
    fi

    cp "$src" "$dest"
    echo "    Installed: $dest"
}

# Install Systemd Units
install_file "./containers/systemd/dns.network"       "$HOME/.config/containers/systemd/dns.network"
install_file "./containers/systemd/pihole.container"  "$HOME/.config/containers/systemd/pihole.container"
install_file "./containers/systemd/unbound.container" "$HOME/.config/containers/systemd/unbound.container"
install_file "./containers/systemd/caddy.container"   "$HOME/.config/containers/systemd/caddy.container"

# Install Configs
install_file "./containers/storage/unbound/unbound.conf"        "$HOME/.config/containers/storage/unbound/unbound.conf"
install_file "./containers/storage/caddy/Caddyfile"             "$HOME/.config/containers/storage/caddy/Caddyfile"
install_file "./containers/storage/pihole/pihole-resolv.conf"   "$HOME/.config/containers/storage/pihole/pihole-resolv.conf"

# FTP Container
echo -e "${GREEN}[+] Setting up FTP Server...${NC}"
mkdir -p "$HOME/ftp_data" "$HOME/ftp_logs"
install_file "./containers/systemd/ftp.container"     "$HOME/.config/containers/systemd/ftp.container"

# --- 4. Permissions ---
echo -e "${GREEN}[+] Fixing permissions for Pi-hole (UID 999)...${NC}"
# This ensures usage of the mapped user ID for rootless podman
podman unshare chown -R 999:999 "$HOME/.config/containers/storage/pihole"

echo -e "${GREEN}[+] Setting file permissions and SELinux contexts...${NC}"
find "$HOME/.config/containers/storage" -type d -exec chmod 755 {} \;
find "$HOME/.config/containers/storage" -type f -exec chmod 644 {} \;
# Apply container_file_t context for read access
chcon -R -t container_file_t "$HOME/.config/containers/storage"

# --- 5. Firewall Configuration ---
echo -e "${GREEN}[+] Configuring Firewall...${NC}"

ensure_port_open() {
    local port=$1
    if ! sudo firewall-cmd --list-ports | grep -q "$port"; then
        echo -e "    Opening port ${YELLOW}$port${NC}..."
        sudo firewall-cmd --permanent --add-port="$port" > /dev/null
        sudo firewall-cmd --reload > /dev/null
    else
        echo -e "    Port $port is already open."
    fi
}

# DNS
ensure_port_open "53/tcp"
ensure_port_open "53/udp"
# Caddy
ensure_port_open "8080/tcp"
ensure_port_open "8443/tcp"
# FTP
ensure_port_open "2121/tcp"
ensure_port_open "2020/tcp"
ensure_port_open "21100-21110/tcp"

# --- 6. Activation ---
echo -e "${GREEN}[+] Reloading systemd and starting services...${NC}"
systemctl --user daemon-reload
systemctl --user enable --now dns-network.service
systemctl --user enable --now unbound.service
systemctl --user enable --now pihole.service
systemctl --user enable --now ftp.service

echo -e "${GREEN}[+] Starting Caddy (might take a moment)...${NC}"
systemctl --user enable --now caddy.service

# Final Check
if systemctl --user is-active --quiet pihole.service; then
    echo -e "${GREEN}[SUCCESS] Stack deployed successfully!${NC}"
    echo "Admin Panel: http://localhost:8080/admin/"
else
    echo -e "${RED}[ERROR] Pi-hole service failed to start. Check logs: podman logs pihole${NC}"
fi