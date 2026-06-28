#!/bin/bash
# ==============================================================================
# Helper Script to Check GitOps Sync Status
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="/var/log/homelab-git-sync.log"
[ ! -f "$LOG_FILE" ] && LOG_FILE="/tmp/homelab-git-sync.log"

echo -e "${CYAN}=== Homelab Git-Sync Status ===${NC}"

# 1. Check Systemd Service Status
echo -n "1. Systemd Service: "
if systemctl is-active --quiet homelab-git-sync.service 2>/dev/null; then
    echo -e "${GREEN}ACTIVE (Running)${NC}"
else
    echo -e "${RED}INACTIVE (Stopped)${NC}"
    echo "   Start it with: sudo systemctl start homelab-git-sync.service"
fi

# 2. Check Git Local Status
echo -n "2. Local Repository Status: "
cd "$(dirname "$0")/.."
if [[ -z $(git status --porcelain) ]]; then
    echo -e "${GREEN}CLEAN (No uncommitted changes)${NC}"
else
    echo -e "${YELLOW}DIRTY (Uncommitted local changes exist)${NC}"
    git status -s
fi

# 3. Check Remote Synchronization Status
echo -n "3. GitHub Synchronization: "
# Force Git to use your private key and avoid blocking on host verification
export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"

if ! git fetch origin main &>/dev/null; then
    echo -e "${RED}ERROR (Failed to connect to GitHub)${NC}"
else
    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse origin/main)

    if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
        echo -e "${GREEN}IN SYNC (GitHub and Local Server match)${NC}"
    else
        BEHIND=$(git rev-list --count HEAD..origin/main)
        AHEAD=$(git rev-list --count origin/main..HEAD)
        
        if [ "$BEHIND" -gt 0 ]; then
            echo -e "${YELLOW}BEHIND by $BEHIND commit(s) (Pending pull)${NC}"
        elif [ "$AHEAD" -gt 0 ]; then
            echo -e "${YELLOW}AHEAD by $AHEAD commit(s) (Pending push)${NC}"
        fi
    fi
fi

# 4. Show Recent Sync Log Entries
echo -e "\n${CYAN}=== Recent Sync Logs ===${NC}"
if [ -f "$LOG_FILE" ]; then
    tail -n 5 "$LOG_FILE"
else
    echo -e "${RED}No log file found at $LOG_FILE${NC}"
fi
