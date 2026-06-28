#!/bin/bash
# ==============================================================================
# Helper Script to Retrieve Service Passwords from Kubernetes Secrets
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ $# -lt 1 ]; then
    echo -e "${RED}[ERROR] Please provide a service name.${NC}"
    echo "Usage: $0 <service-name>"
    echo "Example: $0 pihole"
    exit 1
fi

SERVICE_NAME=$(echo "$1" | tr '[:upper:]' '[:lower:]')
SECRET_NAME=""

# Define custom mappings if the secret name doesn't match <service>-admin
case "$SERVICE_NAME" in
    pihole)
        SECRET_NAME="pihole-admin"
        ;;
    *)
        # Default fallback guess
        SECRET_NAME="${SERVICE_NAME}-admin"
        ;;
esac

# Check if KUBECONFIG is set or fallback to default path
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo -e "${RED}[ERROR] Kubeconfig not found at $KUBECONFIG_PATH.${NC}"
    exit 1
fi

# Verify if secret exists in cluster
if ! kubectl --kubeconfig="$KUBECONFIG_PATH" get secret "$SECRET_NAME" -n default &>/dev/null; then
    # Try checking if secret without "-admin" suffix exists
    if kubectl --kubeconfig="$KUBECONFIG_PATH" get secret "$SERVICE_NAME" -n default &>/dev/null; then
        SECRET_NAME="$SERVICE_NAME"
    else
        echo -e "${RED}[ERROR] No secret found for service '$SERVICE_NAME' (checked '$SECRET_NAME' and '$SERVICE_NAME').${NC}"
        exit 1
    fi
fi

# Extract and decode the password
# Checks standard password keys ('password', 'admin-password', 'token')
for key in password admin-password token; do
    ENCODED_VAL=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get secret "$SECRET_NAME" -n default -o jsonpath="{.data.$key}" 2>/dev/null)
    if [ -n "$ENCODED_VAL" ]; then
        DECODED_VAL=$(echo "$ENCODED_VAL" | base64 --decode)
        echo -e "${GREEN}[SUCCESS] Password for $SERVICE_NAME ($SECRET_NAME -> $key):${NC}"
        echo "$DECODED_VAL"
        exit 0
    fi
done

echo -e "${RED}[ERROR] Secret '$SECRET_NAME' was found, but did not contain standard keys (password, admin-password, token).${NC}"
exit 1
