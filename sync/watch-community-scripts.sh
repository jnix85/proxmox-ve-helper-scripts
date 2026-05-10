#!/bin/bash
# ==============================================================================
# Proxmox Git Sync Watcher
# Description: Uses inotifywait to watch a directory for changes and 
#              automatically triggers the sync script.
# ==============================================================================

REPO_DIR="/usr/local/community-scripts"
SYNC_SCRIPT="/home/jparks/src/proxmox/arr-suite/sync-community-scripts.sh"
LOCK_FILE="/tmp/git-sync.lock"

# Ensure inotifywait is installed
if ! command -v inotifywait &> /dev/null; then
    echo "ERROR: inotifywait is not installed."
    echo "Please install it using: apt-get install inotify-tools"
    exit 1
fi

echo "Starting to watch $REPO_DIR for changes..."

while true; do
    # Wait for a single change event recursively, excluding the .git directory
    inotifywait -q -r -e modify,create,delete,move "$REPO_DIR" --exclude '/\.git/'
    
    # If the lock file exists, the change was caused by our own git pull from another node.
    # We ignore the event to prevent an infinite loop of syncs.
    if [ ! -f "$LOCK_FILE" ]; then
        echo "Change detected by user in $REPO_DIR! Triggering sync..."
        
        # Debounce: Wait 2 seconds to allow multiple file saves/writes to complete
        sleep 2
        
        # Run the sync script
        bash "$SYNC_SCRIPT"
    else
        echo "Change detected, but it was caused by an auto-sync. Ignoring."
    fi
done
