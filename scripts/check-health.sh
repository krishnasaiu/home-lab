#!/bin/bash
# ==============================================================================
# Homelab Application Health Check and Diagnostic Tool
# ==============================================================================
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}           Homelab Application Health Check & Diagnostics        ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Check Kubeconfig / kubectl access
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo -e "${RED}[FAIL] Kubeconfig not found at $KUBECONFIG_PATH. Cannot check cluster health.${NC}"
    exit 1
fi

# 1. Node & Core Cluster Health
echo -e "\n${CYAN}--- Cluster Node Status ---${NC}"
NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$NODE_STATUS" = "True" ]; then
    echo -e "  K3s Control Node: ${GREEN}READY${NC}"
else
    echo -e "  K3s Control Node: ${RED}NOT READY / OFFLINE${NC}"
fi

# Helper to check pod status
check_pod_status() {
    local app_label="$1"
    local friendly_name="$2"
    
    echo -n "  $friendly_name Pod: "
    local pod_info=$(kubectl get pods -l "$app_label" -o jsonpath='{.items[0].status.phase} : {.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
    
    if [[ "$pod_info" =~ "Running : true" ]]; then
        echo -e "${GREEN}RUNNING & READY${NC}"
        return 0
    elif [ -z "$pod_info" ]; then
        echo -e "${RED}NOT FOUND / DELETED${NC}"
        return 1
    else
        echo -e "${RED}ERROR ($pod_info)${NC}"
        # Print logs for diagnostics
        echo -e "${YELLOW}   Recent Logs:${NC}"
        kubectl logs deployment/"$friendly_name" --tail=5 2>/dev/null || kubectl logs -l "$app_label" --tail=5 2>/dev/null
        return 1
    fi
}

# 2. Check Pod Statuses
echo -e "\n${CYAN}--- Container Pod Statuses ---${NC}"
check_pod_status "app=pihole" "pihole"
check_pod_status "app=ftp-server" "ftp-server"
check_pod_status "app=homeassistant" "homeassistant"
check_pod_status "app.kubernetes.io/name=keel" "keel"

# 3. Port Diagnostics (Check if services are listening on the host)
echo -e "\n${CYAN}--- Network Ports Listening States ---${NC}"
check_port() {
    local port="$1"
    local proto="$2"
    local name="$3"
    
    echo -n "  Port $port ($proto - $name): "
    if nc -z -w 2 127.0.0.1 "$port" 2>/dev/null; then
        echo -e "${GREEN}ACTIVE (Listening)${NC}"
    else
        # Try UDP check if protocol is UDP
        if [ "$proto" = "UDP" ] && command -v ss &>/dev/null; then
            if ss -u -a | grep -q ":$port "; then
                echo -e "${GREEN}ACTIVE (Listening)${NC}"
                return 0
            fi
        fi
        echo -e "${RED}INACTIVE (Closed)${NC}"
    fi
}

check_port 53 "UDP" "Pi-hole DNS"
check_port 80 "TCP" "Traefik Ingress Http"
check_port 21 "TCP" "FTP Server Control"
check_port 8123 "TCP" "Home Assistant Web"
check_port 9090 "TCP" "Cockpit Web"

# 4. HTTP and Local Ingress Routing Checks
echo -e "\n${CYAN}--- Web & Ingress Access Checks ---${NC}"
check_http() {
    local url="$1"
    local host_header="$2"
    local name="$3"
    
    echo -n "  $name ($url): "
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host_header" --connect-timeout 2 "$url")
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "401" ] || [ "$http_code" = "301" ]; then
        echo -e "${GREEN}OK (HTTP $http_code)${NC}"
    else
        echo -e "${RED}FAIL (HTTP $http_code)${NC}"
    fi
}

check_http "http://127.0.0.1/admin/" "pihole.homelab" "Pi-hole Ingress"
check_http "http://127.0.0.1/" "homeassistant.homelab" "Home Assistant Ingress"
check_http "http://127.0.0.1:8123/" "localhost" "Home Assistant Direct Port"

# 5. Local DNS Resolution Checks
echo -e "\n${CYAN}--- DNS Resolution Status ---${NC}"
check_dns() {
    local domain="$1"
    echo -n "  Resolve $domain: "
    
    local resolved_ip=$(getent hosts "$domain" | awk '{print $1}' || nslookup "$domain" 127.0.0.1 2>/dev/null | awk '/Address:/ {print $2}' | tail -n 1)
    
    if [ -n "$resolved_ip" ]; then
        echo -e "${GREEN}RESOLVED to $resolved_ip${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi
}

check_dns "pihole.homelab"
check_dns "homeassistant.homelab"

echo -e "${CYAN}=================================================================${NC}"
