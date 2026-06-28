#!/bin/bash
# ==============================================================================
# K3s Bootstrapping Script for Debian Home Lab
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[+] Starting K3s Installation...${NC}"

# 1. Install K3s (disable traefik by default if using custom proxy like Caddy)
# Disable servicelb/traefik if we want to run custom ingress or port forwards
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -s - --disable traefik
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

echo -e "${GREEN}[SUCCESS] K3s bootstrapped! Run 'kubectl get nodes' to verify.${NC}"
