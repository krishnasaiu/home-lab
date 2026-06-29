#!/bin/bash
# ==============================================================================
# Declarative Deployer and Symlink Linker for K3s Homelab
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MANIFESTS_DIR="/var/lib/rancher/k3s/server/manifests"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Ensure script is run with sudo/root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run as root or with sudo.${NC}"
    echo "Usage: sudo $0 <app-name|all>"
    exit 1
fi

# Define our declarative workloads
# Format: app_name | repo_manifest_relative_path | symlink_name | host_dir_to_create (optional)
declare -A MANIFEST_MAP
MANIFEST_MAP[keel]="kubernetes/system/keel/keel-release.yaml:keel-release.yaml:"
MANIFEST_MAP[unbound]="kubernetes/apps/unbound/unbound-config.yaml:unbound-config.yaml:"
MANIFEST_MAP[pihole]="kubernetes/apps/pihole/pihole-release.yaml:pihole-release.yaml:"
MANIFEST_MAP[ftp-server]="kubernetes/apps/ftp-server/ftp-deployment.yaml:ftp-deployment.yaml:/home/krishna/scans"
MANIFEST_MAP[homeassistant]="kubernetes/apps/homeassistant/homeassistant-deployment.yaml:homeassistant-deployment.yaml:/home/krishna/homeassistant_config"

# Print usage
usage() {
    echo -e "${CYAN}=== Homelab Deployer Utility ===${NC}"
    echo "Usage: sudo $0 <app-name|all>"
    echo "Available apps:"
    for app in "${!MANIFEST_MAP[@]}"; do
        echo "  - $app"
    done
    echo "  - all"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

TARGET_APP="$1"

# Function to deploy a specific mapped workload
deploy_workload() {
    local app="$1"
    local config="${MANIFEST_MAP[$app]}"
    
    local repo_path=$(echo "$config" | cut -d':' -f1)
    local symlink_name=$(echo "$config" | cut -d':' -f2)
    local host_dir=$(echo "$config" | cut -d':' -f3)

    echo -e "${CYAN}[+] Deploying app: $app...${NC}"

    # 1. Create host directory if required
    if [ -n "$host_dir" ]; then
        if [ ! -d "$host_dir" ]; then
            echo "   Creating host storage directory: $host_dir"
            mkdir -p "$host_dir"
        fi
        echo "   Setting permissions on host directory to krishna:krishna"
        chown -R krishna:krishna "$host_dir"
    fi

    # 2. Create the symlink in K3s manifest directory
    local src="$REPO_DIR/$repo_path"
    local dest="$MANIFESTS_DIR/$symlink_name"

    if [ ! -f "$src" ]; then
        echo -e "${RED}   [ERROR] Source manifest not found: $src${NC}"
        return 1
    fi

    # Auto-detect if this is a HelmChart and delete existing resource to avoid revision lock
    if grep -q "kind: HelmChart" "$src"; then
        # Parse name and namespace using basic text parsing (safe and doesn't require yq)
        local hc_name=$(grep -A 5 -m 1 "metadata:" "$src" | grep "name:" | awk '{print $2}' | tr -d '"'\''')
        local hc_ns=$(grep -A 5 -m 1 "metadata:" "$src" | grep "namespace:" | awk '{print $2}' | tr -d '"'\''')
        hc_ns=${hc_ns:-kube-system}
        
        if [ -n "$hc_name" ]; then
            echo "   [HelmChart] Detected HelmChart: $hc_name in namespace $hc_ns"
            # Delete the existing HelmChart CRD and wait for it to be completely gone
            if kubectl get helmchart "$hc_name" -n "$hc_ns" &>/dev/null; then
                echo "   [HelmChart] Deleting existing HelmChart resource to clear locks/revisions..."
                kubectl delete helmchart "$hc_name" -n "$hc_ns" --wait=true --timeout=30s || true
            fi
            # Delete the associated helm-install job as well to prevent watcher race conditions
            if kubectl get job "helm-install-$hc_name" -n "$hc_ns" &>/dev/null; then
                echo "   [HelmChart] Deleting old installer job..."
                kubectl delete job "helm-install-$hc_name" -n "$hc_ns" --wait=true --timeout=30s || true
            fi
        fi
    fi

    echo "   Copying K3s manifest: $dest"
    cp -f "$src" "$dest"

    # 3. Touch the symlink to force K3s update
    echo "   Triggering K3s manifest scan..."
    touch -h "$dest"
    
    # Watch if the changes are picked up by K3s Helm controller
    if [ -n "${hc_name:-}" ]; then
        echo -n "   [HelmChart] Watching for K3s to reconcile and run install job (max 2m)..."
        local start_time=$(date +%s)
        local timeout=120
        local success=false
        
        while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
            # Check if K3s has recreated the HelmChart resource and completed the install job
            if kubectl get helmchart "$hc_name" -n "$hc_ns" &>/dev/null; then
                local job_status=$(kubectl get job "helm-install-$hc_name" -n "$hc_ns" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)
                if [ "$job_status" = "True" ]; then
                    echo -e "\r\033[K${GREEN}   [SUCCESS] K3s successfully applied HelmChart updates!${NC}"
                    success=true
                    break
                fi
                echo -ne "\r\033[K   [HelmChart] Status: Recreated. Running installation job..."
            else
                echo -ne "\r\033[K   [HelmChart] Status: Waiting for K3s scan to pick up manifest..."
            fi
            sleep 5
        done
        
        if [ "$success" = false ]; then
            echo -e "\n${RED}   [WARNING] K3s has not completed the HelmChart update after 2 minutes.${NC}"
            echo -e "${YELLOW}   ==> Action Required: Please restart K3s to force a scan: sudo systemctl restart k3s${NC}"
        fi
    fi

    echo -e "${GREEN}[SUCCESS] Deployed $app successfully!${NC}\n"
}

# Run deployment
if [ "$TARGET_APP" = "all" ]; then
    echo -e "${CYAN}=== Deploying ALL workloads to K3s cluster ===${NC}\n"
    # Deploy dependencies first (unbound and keel)
    deploy_workload "keel"
    deploy_workload "unbound"
    deploy_workload "pihole"
    deploy_workload "ftp-server"
    deploy_workload "homeassistant"
elif [ -n "${MANIFEST_MAP[$TARGET_APP]+x}" ]; then
    deploy_workload "$TARGET_APP"
else
    echo -e "${RED}[ERROR] Unknown app: $TARGET_APP${NC}"
    usage
fi
