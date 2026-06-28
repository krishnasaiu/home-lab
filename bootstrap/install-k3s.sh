#!/bin/bash
# ==============================================================================
# K3s Bootstrapping Script for Debian Home Lab
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Helper function to generate a secure random alphanumeric password
generate_password() {
    local length="${1:-16}"
    if command -v openssl &>/dev/null; then
        openssl rand -base64 "$length" | tr -dc 'A-Za-z0-9' | head -c "$length"
    else
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
    fi
}

echo -e "${GREEN}[+] Starting K3s Installation...${NC}"

# 1. Install K3s (disable traefik by default if using custom proxy like Caddy)
# Disable servicelb/traefik if we want to run custom ingress or port forwards
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -
else
    echo "K3s is already installed."
fi

# 2. Setup Kubeconfig for user 'krishna'
echo -e "${GREEN}[+] Configuring Kubeconfig permissions...${NC}"
KUBE_DIR="/home/krishna/.kube"
mkdir -p "$KUBE_DIR"

sudo cp /etc/rancher/k3s/k3s.yaml "$KUBE_DIR/config"
sudo chown krishna:krishna "$KUBE_DIR/config"
chmod 600 "$KUBE_DIR/config"

# Export KUBECONFIG in shell profile if not present
SHELL_PROFILE="/home/krishna/.bashrc"
if ! grep -q "export KUBECONFIG=" "$SHELL_PROFILE"; then
    echo 'export KUBECONFIG="$HOME/.kube/config"' >> "$SHELL_PROFILE"
fi

# 3. Auto-generate secure passwords and store in Kubernetes Secrets
echo -e "${GREEN}[+] Setting up automated secrets...${NC}"
export KUBECONFIG="$KUBE_DIR/config"

if ! kubectl get secret pihole-admin -n default &>/dev/null; then
    PIHOLE_PASSWORD=$(generate_password 16)
    kubectl create secret generic pihole-admin \
        --from-literal=password="$PIHOLE_PASSWORD" \
        -n default
    echo -e "    Generated and created ${GREEN}pihole-admin${NC} secret."
else
    echo "    Secret 'pihole-admin' already exists. Skipping generation."
fi

if ! kubectl get secret ftp-credentials -n default &>/dev/null; then
    FTP_PASSWORD=$(generate_password 12)
    kubectl create secret generic ftp-credentials \
        --from-literal=users="scanner|$FTP_PASSWORD|/scans|1000|1000" \
        -n default
    echo -e "    Generated and created ${GREEN}ftp-credentials${NC} secret."
else
    echo "    Secret 'ftp-credentials' already exists. Skipping creation."
fi

echo -e "${GREEN}[SUCCESS] K3s bootstrapped! Run 'kubectl get nodes' to verify.${NC}"

