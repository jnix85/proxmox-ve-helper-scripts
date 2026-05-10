#!/bin/bash

apt-get update
apt-get install inotify-tools

chmod +x /usr/local/bin/sync-community-scripts.sh
chmod +x /usr/local/bin/watch-community-scripts.sh

cat > /etc/systemd/system/git-sync-watcher.service << EOF
[Unit]
Description=Watch for Git Changes in Community Scripts
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/watch-community-scripts.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable git-sync-watcher.service
systemctl start git-sync-watcher.service
