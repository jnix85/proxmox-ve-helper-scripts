#!/bin/bash

# ==============================================================================
# Proxmox Git Sync Script
# Description: Syncs a local Git repository across multiple Proxmox nodes.
# Assumes SSH key-based authentication is set up between the nodes.
# ==============================================================================

# --- Configuration ---
# The directory you want to keep in sync
REPO_DIR="/usr/local/community-scripts"

# The branch to sync
BRANCH="main"

# List of all your Proxmox nodes (hostnames or IP addresses)
# Update these to match your actual cluster nodes!
NODES=("pve1" "pve2" "pve3" "pve4")

# Remote name (usually origin)
REMOTE="origin"
# ---------------------

CURRENT_NODE=$(hostname)
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
LOCK_FILE="/tmp/git-sync.lock"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    echo "Sync is already running or locked (found $LOCK_FILE). Exiting."
    exit 0
fi
touch "$LOCK_FILE"

# Ensure the lock file is removed when the script exits
trap "rm -f $LOCK_FILE" EXIT


echo "=================================================="
echo "Starting Git Sync at $TIMESTAMP"
echo "Repository: $REPO_DIR"
echo "Executing from: $CURRENT_NODE"
echo "=================================================="

# 1. First, commit and push any local changes from the current node
echo "[1/3] Committing and pushing local changes from $CURRENT_NODE..."
cd "$REPO_DIR" || { echo "ERROR: Directory $REPO_DIR not found on $CURRENT_NODE!"; exit 1; }

# Check if there are any uncommitted changes
if [[ -n $(git status -s) ]]; then
    echo "Found local changes on $CURRENT_NODE. Committing..."
    git add .
    git commit -m "Auto-sync from $CURRENT_NODE at $TIMESTAMP"
else
    echo "No local changes to commit on $CURRENT_NODE."
fi

# Pull with rebase to avoid merge commits if remote changed, then push
echo "Pulling latest changes from $REMOTE..."
git pull --rebase "$REMOTE" "$BRANCH"

echo "Pushing to $REMOTE..."
git push "$REMOTE" "$BRANCH"

# 2. Iterate through all nodes and pull the latest changes
echo ""
echo "[2/3] Syncing remote nodes..."

for NODE in "${NODES[@]}"; do
    if [[ "$NODE" == "$CURRENT_NODE" ]] || [[ "$NODE" == "localhost" ]] || [[ "$NODE" == "127.0.0.1" ]]; then
        # We already synced the current node in step 1
        continue
    fi

    echo "-> Connecting to $NODE..."
    
    # We use SSH to connect to the node, change directory, and pull
    # We also stash any uncommitted changes on the remote nodes to prevent pull errors,
    # then pop them after the pull (or you can remove the stash if you strictly want a 1-way mirror)
    ssh -o ConnectTimeout=5 root@"$NODE" "bash -s" << EOF
        LOCK_FILE="/tmp/git-sync.lock"
        if [ -f "\$LOCK_FILE" ]; then
            echo "   [SKIPPED] Sync is already running on $NODE"
            exit 0
        fi
        touch "\$LOCK_FILE"
        trap "rm -f \$LOCK_FILE" EXIT

        if [ ! -d "$REPO_DIR" ]; then
            echo "   ERROR: Directory $REPO_DIR not found on $NODE"
            exit 1
        fi
        
        cd "$REPO_DIR"
        
        # Check for local changes on the remote node and stash them if they exist
        if [[ -n \$(git status -s) ]]; then
            echo "   Stashing local changes on $NODE..."
            git stash
            STASHED=1
        else
            STASHED=0
        fi

        echo "   Pulling latest from $REMOTE/$BRANCH..."
        git pull --rebase "$REMOTE" "$BRANCH"
        
        if [ "\$STASHED" -eq 1 ]; then
            echo "   Restoring stashed changes on $NODE..."
            git stash pop
        fi
EOF

    if [ $? -eq 0 ]; then
        echo "   [SUCCESS] $NODE is synced."
    else
        echo "   [FAILED] Failed to sync $NODE."
    fi
done

echo ""
echo "[3/3] Sync complete!"
echo "=================================================="
