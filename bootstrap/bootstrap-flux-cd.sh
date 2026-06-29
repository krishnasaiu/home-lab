#!/usr/bin/env bash

set -euo pipefail

# Homelab Flux CD Bootstrapper
# This script installs the Flux CLI, configures local host settings, and bootstraps GitOps.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Homelab Flux CD GitOps Bootstrapper ===${NC}\n"

# 0. Setup Kubeconfig for current user if it does not exist
if [ ! -f "$HOME/.kube/config" ]; then
    echo -e "${YELLOW}[+] Copying Kubeconfig for user '$(whoami)'...${NC}"
    mkdir -p "$HOME/.kube"
    sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
    sudo chown -R "$(whoami)":"$(whoami)" "$HOME/.kube"
    chmod 600 "$HOME/.kube/config"
    
    # Export KUBECONFIG in shell profile if not present
    SHELL_PROFILE="$HOME/.bashrc"
    if [ -f "$SHELL_PROFILE" ]; then
        if ! grep -q "export KUBECONFIG=" "$SHELL_PROFILE"; then
            echo 'export KUBECONFIG="$HOME/.kube/config"' >> "$SHELL_PROFILE"
        fi
    fi
fi

# Check if Flux CD is already bootstrapped in the cluster
FLUX_EXISTS=false
if kubectl get deployment -n flux-system source-controller &>/dev/null; then
    FLUX_EXISTS=true
fi

# 1. Stop old git-sync systemd service if running
if systemctl is-active --quiet homelab-git-sync.service &>/dev/null; then
    echo -e "${YELLOW}[+] Stopping and disabling old homelab-git-sync service...${NC}"
    sudo systemctl disable --now homelab-git-sync.service || true
fi

# 2. Install Flux CLI if not present
if ! command -v flux &>/dev/null; then
    echo -e "${YELLOW}[+] Installing Flux CLI...${NC}"
    curl -s https://fluxcd.io/install.sh | sudo bash
else
    echo -e "${GREEN}[✔] Flux CLI is already installed.${NC}"
fi

# 3. Create namespace and pre-populate cluster-settings ConfigMap with host LAN IP
echo -e "${YELLOW}[+] Generating cluster-settings ConfigMap...${NC}"
HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $(NF-2); exit}' || hostname -I | awk '{print $1}')
HOST_IP=$(echo "$HOST_IP" | xargs)
HOST_IP=${HOST_IP:-127.0.0.1}

echo -e "    Detected LAN IP: ${GREEN}$HOST_IP${NC}"

kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap cluster-settings -n flux-system \
  --from-literal=host_ip="$HOST_IP" \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Pre-populate pihole-admin secret with a clean alphanumeric password if it does not exist
if ! kubectl get secret pihole-admin -n default &>/dev/null; then
    echo -e "${YELLOW}[+] Auto-generating secure alphanumeric password for Pi-hole...${NC}"
    PIHOLE_PASS=$(openssl rand -hex 12)
    kubectl create secret generic pihole-admin -n default --from-literal=password="$PIHOLE_PASS"
    
    # Restart the deployment to pick up the new secret immediately
    echo -e "    Restarting Pi-hole deployment to load the new secret..."
    kubectl rollout restart deployment/pihole -n default &>/dev/null || true
fi

# 5. Pre-populate postgres-credentials secret with a clean alphanumeric password if it does not exist
if ! kubectl get secret postgres-credentials -n default &>/dev/null; then
    echo -e "${YELLOW}[+] Auto-generating secure password for PostgreSQL...${NC}"
    POSTGRES_PASS=$(openssl rand -hex 16)
    kubectl create secret generic postgres-credentials -n default \
      --from-literal=password="$POSTGRES_PASS" \
      --from-literal=db_url_homeassistant="postgresql://postgres:$POSTGRES_PASS@postgres-service.default.svc.cluster.local:5432/homeassistant" \
      --from-literal=db_url_vaultwarden="postgresql://postgres:$POSTGRES_PASS@postgres-service.default.svc.cluster.local:5432/vaultwarden" \
      --from-literal=db_url_paperless="postgresql://postgres:$POSTGRES_PASS@postgres-service.default.svc.cluster.local:5432/paperless"
elif ! kubectl get secret postgres-credentials -n default -o jsonpath="{.data.db_url_paperless}" &>/dev/null; then
    echo -e "${YELLOW}[+] Adding paperless database URL to existing postgres-credentials secret...${NC}"
    # Read existing password to preserve it
    POSTGRES_PASS=$(kubectl get secret postgres-credentials -n default -o jsonpath="{.data.password}" | base64 --decode)
    kubectl delete secret postgres-credentials -n default &>/dev/null || true
    kubectl create secret generic postgres-credentials -n default \
      --from-literal=password="$POSTGRES_PASS" \
      --from-literal=db_url_homeassistant="postgresql://postgres:$POSTGRES_PASS@postgres-service.default.svc.cluster.local:5432/homeassistant" \
      --from-literal=db_url_vaultwarden="postgresql://postgres:$POSTGRES_PASS@postgres-service.default.svc.cluster.local:5432/vaultwarden" \
      --from-literal=db_url_paperless="postgresql://postgres:$POSTGRES_PASS@postgres-service.default.svc.cluster.local:5432/paperless"
fi

# 6. Pre-populate ftp-credentials secret if it does not exist
if ! kubectl get secret ftp-credentials -n default &>/dev/null; then
    echo -e "${YELLOW}[+] Auto-generating secure password for FTP Scanner...${NC}"
    FTP_PASSWORD=$(openssl rand -hex 8)
    kubectl create secret generic ftp-credentials -n default \
      --from-literal=users="scanner|$FTP_PASSWORD|/scans|1000|1000"
fi

# 7. Ensure beszel-credentials secret exists (created manually for security)
if ! kubectl get secret beszel-credentials -n default &>/dev/null; then
    echo -e "${RED}[ERROR] Secret 'beszel-credentials' not found. Please run the following command to create it securely:${NC}"
    echo -e "    kubectl create secret generic beszel-credentials -n default --from-literal=username=\"your_email\" --from-literal=password=\"your_password\""
    exit 1
fi

# 8. Exit early if Flux is already bootstrapped
if [ "$FLUX_EXISTS" = true ]; then
    echo -e "${GREEN}[✔] Flux CD is already running in the cluster. Skipping Git repository link setup.${NC}"
    echo -e "${YELLOW}[+] Triggering reconciliation to apply latest changes...${NC}"
    flux reconcile source git flux-system || true
    echo -e "${GREEN}[SUCCESS] Cluster updated successfully!${NC}"
    exit 0
fi

# -- Below this line, we perform the initial bootstrap setup requiring inputs --

# 9. Ask for GitHub Username & Repository details
read -rp "Enter GitHub Owner/Username [krishnasaiu]: " GH_OWNER
GH_OWNER=${GH_OWNER:-krishnasaiu}

read -rp "Enter GitHub Repository Name [home-lab]: " GH_REPO
GH_REPO=${GH_REPO:-home-lab}

# 10. Ask for GitHub Personal Access Token (PAT) securely
read -rsp "Enter GitHub Personal Access Token (PAT) with repo scope: " GITHUB_TOKEN
echo ""
if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}[ERROR] GitHub Personal Access Token cannot be empty.${NC}"
    exit 1
fi

# Export token for Flux CLI
export GITHUB_TOKEN

# 11. Run Flux Bootstrap
echo -e "${YELLOW}[+] Running Flux Bootstrap on GitHub repository ${GH_OWNER}/${GH_REPO}...${NC}"
flux bootstrap github \
  --owner="$GH_OWNER" \
  --repository="$GH_REPO" \
  --branch=main \
  --path=./kubernetes/flux-system \
  --personal

echo -e "\n${GREEN}[SUCCESS] Flux CD successfully bootstrapped!${NC}"
echo -e "You can monitor the sync progress using: ${CYAN}flux get kustomizations -A${NC}"
