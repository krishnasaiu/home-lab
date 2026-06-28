#!/bin/bash
# ==============================================================================
# GitOps Auto-Sync Daemon for Debian Homelab
# ==============================================================================
set -euo pipefail

# Configurations
REPO_DIR="/home/krishna/home-lab"
BRANCH="main"
SYNC_INTERVAL=60 # Check every 60 seconds
LOG_FILE="/var/log/homelab-git-sync.log"

# Ensure log file exists and is writable
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/homelab-git-sync.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

cd "$REPO_DIR"

log "Starting Git-Sync daemon on branch '$BRANCH'..."

while true; do
    # 1. Fetch latest changes from remote
    if ! git fetch origin "$BRANCH" &>/dev/null; then
        log "[ERROR] Failed to fetch from origin"
        sleep "$SYNC_INTERVAL"
        continue
    fi

    # 2. Check for local modifications
    if [[ -n $(git status --porcelain) ]]; then
        log "[INFO] Local changes detected. Committing and pushing..."
        git add .
        git commit -m "Auto-commit: configurations updated on homelab host"
        
        if git push origin "$BRANCH"; then
            log "[SUCCESS] Local changes pushed successfully"
        else
            log "[ERROR] Push failed. Reverting commit and retrying later..."
            git reset HEAD~1
        fi
    else
        # 3. Check if remote has updates (fast-forward pull if clean)
        LOCAL_HASH=$(git rev-parse HEAD)
        REMOTE_HASH=$(git rev-parse "origin/$BRANCH")

        if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
            log "[INFO] Remote changes detected. Pulling..."
            if git pull --ff-only origin "$BRANCH"; then
                log "[SUCCESS] Pulled changes from GitHub successfully"
            else
                log "[ERROR] Fast-forward pull failed. Resolve conflicts manually."
            fi
        fi
    fi

    sleep "$SYNC_INTERVAL"
done
