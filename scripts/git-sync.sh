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

# Test git configuration on startup and log warnings
if ! git config user.name &>/dev/null || ! git config user.email &>/dev/null; then
    log "[WARN] Git user.name or user.email is not configured on this host. Auto-commits might fail."
fi

while true; do
    # 1. Fetch latest changes from remote
    if ! git fetch origin "$BRANCH" 2>>"$LOG_FILE"; then
        log "[ERROR] Failed to fetch from origin. Check network or SSH keys."
        sleep "$SYNC_INTERVAL"
        continue
    fi

    # 2. Check for local modifications
    if [[ -n $(git status --porcelain) ]]; then
        log "[INFO] Local changes detected. Committing and pushing..."
        
        # We run git commands and redirect stdout/stderr to log file to capture errors
        if git add . 2>>"$LOG_FILE"; then
            # We use "|| true" to prevent set -e from killing the script if commit fails (e.g. no config)
            if git commit -m "Auto-commit: configurations updated on homelab host" >>"$LOG_FILE" 2>&1; then
                if git push origin "$BRANCH" >>"$LOG_FILE" 2>&1; then
                    log "[SUCCESS] Local changes pushed successfully"
                else
                    log "[ERROR] Push failed. Reverting local commit..."
                    git reset --soft HEAD~1 2>>"$LOG_FILE"
                fi
            else
                log "[ERROR] Git commit failed. Check if user.name and user.email are set."
            fi
        else
            log "[ERROR] Git add failed."
        fi
    else
        # 3. Check if remote has updates (fast-forward pull if clean)
        LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")
        REMOTE_HASH=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "")

        if [[ -n "$LOCAL_HASH" && -n "$REMOTE_HASH" && "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
            log "[INFO] Remote changes detected. Pulling..."
            if git pull --ff-only origin "$BRANCH" >>"$LOG_FILE" 2>&1; then
                log "[SUCCESS] Pulled changes from GitHub successfully"
            else
                log "[ERROR] Fast-forward pull failed. Resolve conflicts manually."
            fi
        fi
    fi

    sleep "$SYNC_INTERVAL"
done

