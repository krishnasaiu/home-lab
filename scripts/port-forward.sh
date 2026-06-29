#!/bin/bash
# ==============================================================================
# Port Forwarding Helper Script for Homelab
# ==============================================================================
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Resolve kubeconfig path (default to ~/.kube/config-homelab or KUBECONFIG env var)
if [ -n "${KUBECONFIG:-}" ]; then
    KUBECONFIG_PATH="$KUBECONFIG"
elif [ -f "$HOME/.kube/config-homelab" ]; then
    KUBECONFIG_PATH="$HOME/.kube/config-homelab"
elif [ -f "$HOME/.kube/config" ]; then
    KUBECONFIG_PATH="$HOME/.kube/config"
else
    echo -e "${RED}[ERROR] Kubeconfig not found. Checked KUBECONFIG env var, ~/.kube/config-homelab, and ~/.kube/config.${NC}"
    exit 1
fi

if [ $# -lt 1 ]; then
    echo -e "${YELLOW}Usage: $0 [postgres | vaultwarden | paperless | all]${NC}"
    echo "  postgres    - Forwards PostgreSQL port 5432 (for DBeaver)"
    echo "  vaultwarden - Forwards Vaultwarden port 8080 (for Subtle Crypto API)"
    echo "  paperless   - Forwards Paperless-ngx port 8000"
    echo "  all         - Forwards all three services in background tasks"
    exit 1
fi

SERVICE_NAME="$1"

forward_service() {
    local svc="$1"
    local local_port="$2"
    local container_port="$3"
    
    echo -e "${GREEN}[+] Forwarding service/$svc ($container_port -> local $local_port)...${NC}"
    kubectl --kubeconfig="$KUBECONFIG_PATH" port-forward "service/$svc" "$local_port:$container_port" -n default
}

case "$SERVICE_NAME" in
    postgres|postgresql|db)
        forward_service "postgres-service" "5432" "5432"
        ;;
    vaultwarden|bitwarden)
        forward_service "vaultwarden-service" "8080" "8080"
        ;;
    paperless|doc|documents)
        forward_service "paperless-service" "8000" "8000"
        ;;
    all)
        echo -e "${GREEN}[+] Starting port forwards in the background...${NC}"
        kubectl --kubeconfig="$KUBECONFIG_PATH" port-forward "service/postgres-service" 5432:5432 -n default &
        PID_PG=$!
        kubectl --kubeconfig="$KUBECONFIG_PATH" port-forward "service/vaultwarden-service" 8080:8080 -n default &
        PID_VW=$!
        kubectl --kubeconfig="$KUBECONFIG_PATH" port-forward "service/paperless-service" 8000:8000 -n default &
        PID_PL=$!
        
        echo -e "    PostgreSQL PID: ${CYAN}$PID_PG${NC}"
        echo -e "    Vaultwarden PID: ${CYAN}$PID_VW${NC}"
        echo -e "    Paperless-ngx PID: ${CYAN}$PID_PL${NC}"
        echo -e "${YELLOW}[TIP] Press Ctrl+C to terminate all background forwards.${NC}"
        
        # Capture Ctrl+C and kill background forwards automatically
        trap "kill $PID_PG $PID_VW $PID_PL 2>/dev/null || true; echo -e '\n${GREEN}[+] Port forwards closed.${NC}'; exit" INT TERM EXIT
        wait
        ;;
    *)
        echo -e "${RED}[ERROR] Unknown service '$SERVICE_NAME'. Supported: postgres, vaultwarden, paperless, all.${NC}"
        exit 1
        ;;
esac
