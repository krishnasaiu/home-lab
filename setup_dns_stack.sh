#!/bin/bash
set -e

# ==============================================================================
# Rootless Podman Home Lab Setup Script
# ==============================================================================
# usage: ./setup_dns_stack.sh [--link] [service_name ...]
# examples:
#   ./setup_dns_stack.sh --link           # Installs EVERYTHING using symlinks
#   ./setup_dns_stack.sh pihole ftp       # Installs only Pi-hole and FTP (copy)
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

USE_SYMLINK=false

# --- Helper Functions ---

install_file() {
    local src="$1"
    local dest="$2"
    
    if [ ! -f "$src" ]; then
        echo -e "${RED}[ERROR] Missing source file: $src${NC}"
        exit 1
    fi
    mkdir -p "$(dirname "$dest")" # Ensure parent dir exists

    if [ "$USE_SYMLINK" = true ]; then
        local abs_src
        abs_src=$(readlink -f "$src")
        
        # Check if destination exists
        if [ -e "$dest" ] || [ -L "$dest" ]; then
             # If it's already the correct symlink, skip
             if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$abs_src" ]; then
                 echo "    Linked: $dest (Up to date)"
                 return
             fi
             # Backup existing file/link
             mv "$dest" "${dest}.bak"
        fi
        
        ln -s "$abs_src" "$dest"
        echo "    Linked: $dest -> $abs_src"
    else
        # Copy mode
        if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
            cp "$dest" "${dest}.bak"
        fi
        cp "$src" "$dest"
        echo "    Installed: $dest"
    fi
}

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

check_prerequisites() {
    echo -e "${GREEN}[+] Checking prerequisites...${NC}"
    if ! command -v podman &> /dev/null; then
        echo -e "${RED}[ERROR] Podman is not installed.${NC}"
        exit 1
    fi
    if [ ! -d "./containers" ]; then
        echo -e "${RED}[ERROR] Project directory './containers' not found.${NC}"
        exit 1
    fi
    # Check secrets (soft check, warn if missing for generic use)
    if ! podman secret exists ftp_secret; then
         echo -e "${YELLOW}[WARN] Secret 'ftp_secret' is missing.${NC} (Required for FTP)"
    fi
}

# --- Service Functions ---

setup_base() {
    echo -e "${GREEN}[+] Setting up Base Stack (Network, Caddy, Unbound)...${NC}"
    
    # 1. Directories
    mkdir -p ~/.config/containers/systemd/
    mkdir -p ~/.config/containers/storage/unbound
    mkdir -p ~/.config/containers/storage/caddy/{caddy-config,caddy-data,Caddyfile_dir}

    # 2. Files
    install_file "./containers/systemd/dns.network"       "$HOME/.config/containers/systemd/dns.network"
    install_file "./containers/systemd/caddy.container"   "$HOME/.config/containers/systemd/caddy.container"
    install_file "./containers/systemd/unbound.container" "$HOME/.config/containers/systemd/unbound.container"
    install_file "./containers/storage/unbound/unbound.conf" "$HOME/.config/containers/storage/unbound/unbound.conf"
    install_file "./containers/storage/caddy/Caddyfile"      "$HOME/.config/containers/storage/caddy/Caddyfile"
    
    # 3. Permissions (Unbound/Caddy config)
    chcon -R -t container_file_t "$HOME/.config/containers/storage"

    # 4. Firewall (Base ports)
    ensure_port_open "8080/tcp"
    ensure_port_open "8443/tcp" # Caddy
    
    # 5. Service Activation
    systemctl --user daemon-reload
    systemctl --user enable --now dns-network.service
    systemctl --user enable --now unbound.service
    systemctl --user start unbound.service
    check_service_status "unbound.service"
    
    systemctl --user enable --now caddy.service
    systemctl --user start caddy.service
    check_service_status "caddy.service"
}

setup_pihole() {
    echo -e "${GREEN}[+] Setting up Pi-hole...${NC}"
    mkdir -p ~/.config/containers/storage/pihole/{etc-pihole,etc-dnsmasq.d,logs}
    
    install_file "./containers/systemd/pihole.container"  "$HOME/.config/containers/systemd/pihole.container"
    install_file "./containers/storage/pihole/pihole-resolv.conf" "$HOME/.config/containers/storage/pihole/pihole-resolv.conf"
    
    # Fix Permissions
    podman unshare chown -R 999:999 "$HOME/.config/containers/storage/pihole"
    chcon -R -t container_file_t "$HOME/.config/containers/storage/pihole"
    
    ensure_port_open "53/tcp"
    ensure_port_open "53/udp"
    
    systemctl --user daemon-reload
    systemctl --user enable --now pihole.service
    systemctl --user start pihole.service
    check_service_status "pihole.service"
}

setup_ftp() {
    echo -e "${GREEN}[+] Setting up FTP...${NC}"
    mkdir -p "$HOME/ftp_data" "$HOME/ftp_logs"
    install_file "./containers/systemd/ftp.container" "$HOME/.config/containers/systemd/ftp.container"
    
    ensure_port_open "2121/tcp"
    ensure_port_open "2020/tcp"
    ensure_port_open "21100-21110/tcp"
    
    systemctl --user daemon-reload
    systemctl --user enable --now ftp.service
    systemctl --user start ftp.service
    check_service_status "ftp.service"
}

setup_homeassistant() {
    echo -e "${GREEN}[+] Setting up Home Assistant...${NC}"
    mkdir -p "$HOME/homeassistant_config"
    install_file "./containers/systemd/homeassistant.container" "$HOME/.config/containers/systemd/homeassistant.container"
    
    if [ ! -f "$HOME/homeassistant_config/configuration.yaml" ]; then
        install_file "./containers/storage/homeassistant/configuration.yaml" "$HOME/homeassistant_config/configuration.yaml"
    fi
    
    ensure_port_open "8123/tcp"
    
    systemctl --user daemon-reload
    systemctl --user enable --now homeassistant.service
    systemctl --user start homeassistant.service
    check_service_status "homeassistant.service"
}

setup_grocy() {
    echo -e "${GREEN}[+] Setting up Grocy...${NC}"
    mkdir -p "$HOME/grocy_config"
    install_file "./containers/systemd/grocy.container" "$HOME/.config/containers/systemd/grocy.container"
    
    ensure_port_open "9283/tcp"
    
    systemctl --user daemon-reload
    systemctl --user enable --now grocy.service
    systemctl --user start grocy.service
    check_service_status "grocy.service"
}

check_service_status() {
    local service="$1"
    echo -n "    Verifying $service... "
    if systemctl --user is-active --quiet "$service"; then
        echo -e "${GREEN}active${NC}"
    else
        echo -e "${RED}failed${NC}"
        echo "    Logs: journalctl --user -u $service -n 10 --no-pager"
        return 1
    fi
}

setup_vaultwarden() {
    echo -e "${GREEN}[+] Setting up Vaultwarden (Bitwarden)...${NC}"
    mkdir -p "$HOME/vaultwarden_data"
    install_file "./containers/systemd/vaultwarden.container" "$HOME/.config/containers/systemd/vaultwarden.container"
    
    ensure_port_open "8001/tcp"
    
    systemctl --user daemon-reload
    systemctl --user enable --now vaultwarden.service
    systemctl --user start vaultwarden.service
    check_service_status "vaultwarden.service"
}

setup_komodo() {
    echo -e "${GREEN}[+] Setting up Komodo...${NC}"
    mkdir -p "$HOME/komodo_data"
    install_file "./containers/storage/komodo/config.toml" "$HOME/.config/containers/storage/komodo/config.toml"
    install_file "./containers/systemd/komodo.container" "$HOME/.config/containers/systemd/komodo.container"
    
    ensure_port_open "9120/tcp"
    
    systemctl --user daemon-reload
    systemctl --user enable --now komodo.service
    systemctl --user start komodo.service
    check_service_status "komodo.service"
}

setup_paperless() {
    echo -e "${GREEN}[+] Setting up Paperless-ngx...${NC}"
    mkdir -p "$HOME/paperless_data" "$HOME/paperless_media"
    
    install_file "./containers/systemd/paperless-redis.container" "$HOME/.config/containers/systemd/paperless-redis.container"
    install_file "./containers/systemd/paperless-web.container" "$HOME/.config/containers/systemd/paperless-web.container"
    
    ensure_port_open "8000/tcp"
    
    systemctl --user daemon-reload
    systemctl --user enable --now paperless-redis.service
    systemctl --user start paperless-redis.service
    check_service_status "paperless-redis.service"
    
    systemctl --user enable --now paperless-web.service
    systemctl --user start paperless-web.service
    check_service_status "paperless-web.service"
}

setup_dispatcharr() {
    echo -e "${GREEN}[+] Setting up Dispatcharr...${NC}"
    mkdir -p ~/.config/storage/dispatcharr
    
    install_file "./containers/systemd/dispatcharr.container" "$HOME/.config/containers/systemd/dispatcharr.container"
    
    ensure_port_open "9191/tcp"
    
    systemctl --user daemon-reload
    systemctl --user enable --now dispatcharr.service
    systemctl --user start dispatcharr.service
    check_service_status "dispatcharr.service"
}

# --- Main Execution ---

PROJECT_SERVICES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --link|-l)
            USE_SYMLINK=true
            shift
            ;;
        *)
            PROJECT_SERVICES+=("$1")
            shift
            ;;
    esac
done

check_prerequisites

if [ ${#PROJECT_SERVICES[@]} -eq 0 ]; then
    # Default: Install ALL
    setup_base
    setup_pihole
    setup_ftp
    setup_homeassistant
    setup_grocy
    setup_vaultwarden
    setup_komodo
    setup_dispatcharr
    setup_paperless
else
    # Install requested components
    for service in "${PROJECT_SERVICES[@]}"; do
        case $service in
            base) setup_base ;;
            pihole) setup_pihole ;;
            ftp) setup_ftp ;;
            homeassistant|ha) setup_homeassistant ;;
            grocy) setup_grocy ;;
            vaultwarden|bitwarden) setup_vaultwarden ;;
            komodo) setup_komodo ;;
            dispatcharr) setup_dispatcharr ;;
            paperless|ngx) setup_paperless ;;
            *) echo -e "${RED}[ERROR] Unknown service: $service${NC}"; exit 1 ;;
        esac
    done
    # Always restart Caddy at the end of a partial update to ensure config re-read
    systemctl --user restart caddy.service
fi

echo -e "${GREEN}[SUCCESS] Requested services deployed.${NC}"