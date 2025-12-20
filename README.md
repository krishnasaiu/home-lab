# HomeLab - Rootless Podman DNS & Proxy Stack
1. Overview
This project deploys a defined stack of Pi-hole, Unbound, and Caddy using Rootless Podman and Quadlet.

2. System Architecture
Network
Network: 
dns.network
 (Bridge)
Subnet: 10.89.0.0/24
Static IP & Port Map
Service	Static IP	Internal Ports	Host Ports
Pi-hole	10.89.0.10	80, 53	53 (UDP/TCP)
Unbound	10.89.0.20	53	-
Caddy	10.89.0.30	80, 443	8080, 8443
3. Replication Guide
Prerequisites
Install Podman:

sudo dnf install podman container-tools -y
Configure Firewall (Fedora/firewalld):

# DNS Ports
sudo firewall-cmd --permanent --add-port=53/tcp
sudo firewall-cmd --permanent --add-port=53/udp
# Caddy Proxy Ports
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=8443/tcp
# Reload
sudo firewall-cmd --reload
Deployment Commands
Step 1: Create Secrets Securely store passwords and tokens so they aren't exposed in config files:

# Pi-hole Web Admin Password
printf "your_secure_password" | podman secret create my_secret -
# DuckDNS Token (if used)
printf "your_duckdns_token" | podman secret create duckdns_api_token -
Step 2: Create Directory Structure Run as non-root user:

mkdir -p ~/.config/containers/systemd/
mkdir -p ~/.config/containers/storage/pihole/{etc-pihole,etc-dnsmasq.d,logs}
mkdir -p ~/.config/containers/storage/unbound
mkdir -p ~/.config/containers/storage/caddy/{caddy-config,caddy-data,Caddyfile_dir}
Step 3: Place Configuration Files Ensure the following files are copied to their respective locations:

Quadlet Units -> ~/.config/containers/systemd/
dns.network
pihole.container
unbound.container
caddy.container
Configs -> ~/.config/containers/storage/...
unbound/unbound.conf
caddy/Caddyfile
pihole/pihole-resolv.conf (Content: nameserver 10.89.0.20)
Step 4: Fix Permissions (CRITICAL) Because Pi-hole runs as internal user 999, you must map the volume ownership:

podman unshare chown -R 999:999 ~/.config/containers/storage/pihole
Step 5: Start Services

# Reload Systemd to generate units
systemctl --user daemon-reload
# Enable and Start Stack
systemctl --user enable --now dns-network.service
systemctl --user enable --now unbound.service
systemctl --user enable --now pihole.service
systemctl --user enable --now caddy.service
4. Debugging & Verification
1. Verify Caddy (Reverse Proxy)
Check if Caddy is listening and routing correctly.

# Check if listening on host ports
sudo ss -tulpn | grep caddy
# Test Proxy Response (Should be HTTP 200 or 302 to login)
curl -I http://localhost:8080/admin/
# Check Caddy Logs for Access/Errors
journalctl --user -u caddy -n 20
2. Verify Proxy Enforcement (Security)
Ensure Pi-hole cannot be accessed directly, forcing all traffic through Caddy.

# Try to access Pi-hole's internal port directly from Host (Should FAIL)
curl -I --connect-timeout 2 http://127.0.0.1:80/admin/
# Output: curl: (7) Failed to connect... (Connection refused)
# Try to access Pi-hole's old exposed port 8888 (We removed this, so it should FAIL)
curl -I --connect-timeout 2 http://127.0.0.1:8888/admin/
# Output: curl: (7) Failed to connect... (Connection refused)
3. Verify Unbound (Recursive DNS)
Confirm that Pi-hole is actually using Unbound and Unbound is resolving.

# 1. Test Unbound directly (simulating a query from inside the network)
# We use the pihole container to run dig against the unbound container IP
podman exec -it pihole dig google.com @10.89.0.20
# Output: status: NOERROR
# 2. Test Pi-hole Upstream
# Run a specific query against Pi-hole and verify it answers
podman exec -it pihole dig google.com @127.0.0.1
4. General Health
# Check all container IPs
podman inspect -f '{{.Name}} - {{.NetworkSettings.Networks.dns.IPAddress}}' pihole unbound caddy
# Status of Services
systemctl --user status pihole caddy unbound
5. Adding New Services
To add a service (e.g., Home Assistant):

Create homeassistant.container with IP=10.89.0.40.
Update 
caddy.container
 to publish port 8123.
Add entry to 
Caddyfile
: reverse_proxy 10.89.0.40:8123.