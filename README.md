# HomeLab - Rootless Podman DNS & Proxy Stack

## 1. Overview
This project deploys a defined stack of **Pi-hole**, **Unbound**, and **Caddy** using Rootless Podman and Quadlet.

## 2. System Architecture

### Network
- **Network**: [dns.network](file:///home/krishna/.gemini/antigravity/scratch/dns.network) (Bridge)
- **Subnet**: `10.89.0.0/24`

### Static IP & Port Map
| Service | Static IP | Internal Ports | Host Ports |
| :--- | :--- | :--- | :--- |
| **Pi-hole** | `10.89.0.10` | 80, 53 | 53 (UDP/TCP) |
| **Unbound** | `10.89.0.20` | 53 | - |
| **Caddy** | `10.89.0.30` | 80, 443 | 8080, 8443 |
| **FTP** | `10.89.0.40` | 20, 21, 21100-21110 | 2020, 2121, 21100-21110 |
| **Home Assistant** | `10.89.0.50` | 8123 | 8123 |
| **Grocy** | `10.89.0.60` | 9283 | 9283 |
| **Vaultwarden** | `10.89.0.80` | 80 | 8001 |
| **Komodo** | `10.89.0.90` | 9120 | 9120 |
| **Paperless** | `10.89.0.70` | 8000 | 8000 |

---

## 3. Replication Guide

### Prerequisites
1.  **Install Podman**:
    ```bash
    sudo dnf install podman container-tools -y
    ```

2.  **Configure Firewall** (Fedora/firewalld):
    ```bash
    # DNS Ports
    sudo firewall-cmd --permanent --add-port=53/tcp
    sudo firewall-cmd --permanent --add-port=53/udp
    # Caddy Proxy Ports
    sudo firewall-cmd --permanent --add-port=8080/tcp
    sudo firewall-cmd --permanent --add-port=8443/tcp
    # FTP Ports
    sudo firewall-cmd --permanent --add-port=2121/tcp
    sudo firewall-cmd --permanent --add-port=2020/tcp
    sudo firewall-cmd --permanent --add-port=21100-21110/tcp
    # Home Assistant
    sudo firewall-cmd --permanent --add-port=8123/tcp
    # Grocy
    sudo firewall-cmd --permanent --add-port=9283/tcp
    # New Services
    sudo firewall-cmd --permanent --add-port=8001/tcp  # Vaultwarden
    sudo firewall-cmd --permanent --add-port=9120/tcp  # Komodo
    sudo firewall-cmd --permanent --add-port=8000/tcp  # Paperless
    # Reload
    sudo firewall-cmd --reload
    ```

### Deployment Commands

**Step 1: Create Secrets**
Securely store passwords and tokens so they aren't exposed in config files:
```bash
# Pi-hole Web Admin Password
printf "your_secure_password" | podman secret create my_secret -

# DuckDNS Token (if used)
printf "your_duckdns_token" | podman secret create duckdns_api_token -
```

**Step 2: Create Directory Structure**
Run as non-root user:
```bash
mkdir -p ~/.config/containers/systemd/
mkdir -p ~/.config/containers/storage/pihole/{etc-pihole,etc-dnsmasq.d,logs}
mkdir -p ~/.config/containers/storage/unbound
mkdir -p ~/.config/containers/storage/caddy/{caddy-config,caddy-data,Caddyfile_dir}
```

**Step 3: Configuration Strategy (Choose One)**

**Option A: Git Repository Symlink (Recommended)**
If you are cloning this project from Git, link the files instead of copying. This lets you edit files in your repo and just reload systemd to apply changes.
```bash
# Backup existing (just in case)
mv ~/.config/containers/systemd ~/.config/containers/systemd.bak 2>/dev/null || true

# Symlink systemd units (Quadlet files)
# Assuming you are in the root of your git project
ln -s $(pwd)/containers/systemd/*.container ~/.config/containers/systemd/
ln -s $(pwd)/containers/systemd/*.network ~/.config/containers/systemd/

# Symlink Config Files
# Pi-hole
rm -f ~/.config/containers/storage/pihole/pihole-resolv.conf
ln -s $(pwd)/containers/storage/pihole/pihole-resolv.conf ~/.config/containers/storage/pihole/pihole-resolv.conf

# Unbound
rm -f ~/.config/containers/storage/unbound/unbound.conf
ln -s $(pwd)/containers/storage/unbound/unbound.conf ~/.config/containers/storage/unbound/unbound.conf

# Caddy
rm -f ~/.config/containers/storage/caddy/Caddyfile
ln -s $(pwd)/containers/storage/caddy/Caddyfile ~/.config/containers/storage/caddy/Caddyfile
```

**Option B: Direct Copy**
Ensure the following files are copied to their respective locations:

*   **Quadlet Units** -> `~/.config/containers/systemd/`
    *   [dns.network](file:///home/krishna/.gemini/antigravity/scratch/dns.network)
    *   [pihole.container](file:///home/krishna/.gemini/antigravity/scratch/pihole.container)
    *   [unbound.container](file:///home/krishna/.gemini/antigravity/scratch/unbound.container)
    *   [caddy.container](file:///home/krishna/.gemini/antigravity/scratch/caddy.container)
*   **Configs** -> `~/.config/containers/storage/...`
    *   `unbound/unbound.conf`
    *   `caddy/Caddyfile`
    *   `pihole/pihole-resolv.conf` (Content: `nameserver 10.89.0.20`)

**Step 4: Deploy Stack**
The setup script automates permissions, firewall, and service startup. It also supports modular installation.

```bash
# Option A: Install EVERYTHING (Default)
./setup_dns_stack.sh

# Option B: Install specific services
./setup_dns_stack.sh vaultwarden komodo paperless
```

The script will:
1.  Check prerequisites.
2.  Install Quadlet files.
3.  Set permissions and SELinux contexts.
4.  Configure Firewall.
5.  Start Systemd services.

---

## 4. Advanced Debugging & Verification

### 1. Verify Caddy (Reverse Proxy)
Check if Caddy is listening and routing correctly.
```bash
# Check if listening on host ports
sudo ss -tulpn | grep caddy

# Test Proxy Response (Should be HTTP 200 or 302 to login)
curl -I http://localhost:8080/admin/

# Check Caddy Logs for Access/Errors
journalctl --user -u caddy -n 20
```

## Configuration Tips
### Grocy: Change Currency to INR
To update the currency without entering an interactive editor, use `sed` within the container's namespace:
```bash
podman unshare sed -i "s/Setting('CURRENCY', 'USD');/Setting('CURRENCY', 'INR');/" ~/grocy_config/data/config.php
systemctl --user restart grocy
```

### 2. Connect to FTP
Since standard `ftp` clients are often missing from modern OSs (like macOS), use one of the following:

*   **GUI Clients (Recommended)**: FileZilla, Cyberduck, or WinSCP.
    *   **Protocol**: FTP (File Transfer Protocol)
    *   **Encryption**: Use "Only use plain FTP (insecure)" or "Require explicit FTP over TLS" if configured.
    *   **Port**: `2121`
*   **macOS Finder**:
    *   `Go` -> `Connect to Server` (Cmd+K)
    *   Address: `ftp://192.168.50.120:2121`
    *   *Note: Finder is often Read-Only.*
*   **Command Line (macOS)**:
    *   Install generic ftp: `brew install inetutils`
    *   Or use `lftp`: `brew install lftp`
    *   Connect: `ftp -P 2121 192.168.50.120`

### 3. Verify Proxy Enforcement (Security)
Ensure Pi-hole cannot be accessed directly, forcing all traffic through Caddy.
```bash
# Try to access Pi-hole's internal port directly from Host (Should FAIL)
curl -I --connect-timeout 2 http://127.0.0.1:80/admin/
# Output: curl: (7) Failed to connect... (Connection refused)

# Try to access Pi-hole's old exposed port 8888 (We removed this, so it should FAIL)
curl -I --connect-timeout 2 http://127.0.0.1:8888/admin/
# Output: curl: (7) Failed to connect... (Connection refused)
```

### 3. Verify Unbound (Recursive DNS)
Confirm that Pi-hole is actually using Unbound and Unbound is resolving.
```bash
# 1. Test Unbound directly (simulating a query from inside the network)
# We use the pihole container to run dig against the unbound container IP
podman exec -it pihole dig google.com @10.89.0.20
# Output: status: NOERROR

# 2. Test Pi-hole Upstream
# Run a specific query against Pi-hole and verify it answers
podman exec -it pihole dig google.com @127.0.0.1
```

### 4. General Health
```bash
# Check all container IPs
podman inspect -f '{{.Name}} - {{.NetworkSettings.Networks.dns.IPAddress}}' pihole unbound caddy

# Status of Services
systemctl --user status pihole caddy unbound
```

## 5. Adding New Services
To add a service (e.g., Home Assistant):
1.  Create `homeassistant.container` with `IP=10.89.0.40` and `Network=dns.network`.
2.  Update [caddy.container](file:///home/krishna/.gemini/antigravity/scratch/caddy.container) to publish port `8123`.
3.  Add entry to [Caddyfile](file:///home/krishna/.gemini/antigravity/scratch/Caddyfile): `reverse_proxy 10.89.0.40:8123`.