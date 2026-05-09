#!/usr/bin/env bash

# Proxmox VE Helper Script for ESPConnect
# Terminates on a random port without SSL.

set -e

# Terminal Colors
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

function header_info {
clear
cat <<"EOF"
    ___________ ____  ______                            __ 
   / ____/ ___// __ \/ ____/___  ____  ____  ___  _____/ /_
  / __/  \__ \/ /_/ / /   / __ \/ __ \/ __ \/ _ \/ ___/ __/
 / /___ ___/ / ____/ /___/ /_/ / / / / / / /  __/ /__/ /_  
/_____//____/_/    \____/\____/_/ /_/_/ /_/\___/\___/\__/  
                                                           
EOF
}

header_info
echo -e "${BL}[*] Starting ESPConnect LXC setup...${CL}"

# Check if script is run on Proxmox VE
if ! command -v pveam &> /dev/null; then
    echo -e "${RD}[!] This script must be run on a Proxmox VE node.${CL}"
    exit 1
fi

# 1. Update templates and find Debian 12
echo -e "${YW}[*] Updating Proxmox template lists...${CL}"
pveam update >/dev/null 2>&1

TEMPLATE=$(pveam available -section system | awk '{print $2}' | grep "debian-12-standard" | sort -V | tail -n 1)
if [ -z "$TEMPLATE" ]; then
    echo -e "${RD}[!] Failed to find Debian 12 template.${CL}"
    exit 1
fi

echo -e "${YW}[*] Downloading template: $TEMPLATE...${CL}"
pveam download local "$TEMPLATE" >/dev/null 2>&1 || true

# 2. Get next CTID
CTID=$(pvesh get /cluster/nextid)
echo -e "${YW}[*] Using Container ID: ${CTID}${CL}"

# 3. Find suitable storage for rootdir
STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1}' | head -n 1)
if [ -z "$STORAGE" ]; then
    echo -e "${RD}[!] No suitable storage found for LXC containers.${CL}"
    exit 1
fi
echo -e "${YW}[*] Using Storage: ${STORAGE}${CL}"

# 4. Create LXC
echo -e "${YW}[*] Creating LXC container...${CL}"
pct create "$CTID" "local:vztmpl/$TEMPLATE" \
    -arch amd64 \
    -hostname espconnect \
    -net0 name=eth0,bridge=vmbr0,ip=dhcp \
    -features nesting=1 \
    -ostype debian \
    -storage "$STORAGE" \
    -unprivileged 1 \
    -cores 1 \
    -memory 512 \
    -swap 0 >/dev/null 2>&1

# 5. Start LXC
echo -e "${YW}[*] Starting container...${CL}"
pct start "$CTID"
echo -e "${YW}[*] Waiting for container to boot and obtain IP...${CL}"
sleep 5 # give it a moment to boot

# Wait until network is up
IP_ADDRESS=""
for i in {1..20}; do
    IP_CHECK=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
    if [ -n "$IP_CHECK" ]; then
        IP_ADDRESS="$IP_CHECK"
        break
    fi
    sleep 2
done

if [ -z "$IP_ADDRESS" ]; then
    echo -e "${RD}[!] Failed to retrieve IP address. The container might not have network access.${CL}"
    echo -e "${RD}[!] Continuing setup anyway, but final URL might be missing IP.${CL}"
fi

# 6. Inject install script
echo -e "${YW}[*] Injecting setup script into container...${CL}"
cat << 'EOF' > /tmp/espconnect-install.sh
#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive

echo "Updating APT packages..."
apt-get update -y >/dev/null 2>&1
apt-get install -y curl git gnupg nginx >/dev/null 2>&1

echo "Installing Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
apt-get install -y nodejs >/dev/null 2>&1

echo "Cloning ESPConnect repository..."
git clone https://github.com/thelastoutpostworkshop/ESPConnect.git /opt/ESPConnect >/dev/null 2>&1
cd /opt/ESPConnect

echo "Building ESPConnect..."
npm install >/dev/null 2>&1
npm run build >/dev/null 2>&1

# Generate random port between 1024 and 65535
RANDOM_PORT=$(shuf -i 2000-65000 -n 1)

echo "Configuring Nginx on port $RANDOM_PORT..."
cat <<NGINX_CONF > /etc/nginx/sites-available/espconnect
server {
    listen ${RANDOM_PORT};
    listen [::]:${RANDOM_PORT};
    server_name _;

    root /opt/ESPConnect/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX_CONF

ln -s /etc/nginx/sites-available/espconnect /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

systemctl restart nginx

# Save information
echo "$RANDOM_PORT" > /root/random_port.txt
EOF

pct push "$CTID" /tmp/espconnect-install.sh /root/espconnect-install.sh
pct exec "$CTID" -- chmod +x /root/espconnect-install.sh

echo -e "${YW}[*] Installing dependencies and building ESPConnect (this may take a few minutes)...${CL}"
pct exec "$CTID" -- /root/espconnect-install.sh

# 7. Retrieve info and finish
RANDOM_PORT=$(pct exec "$CTID" -- cat /root/random_port.txt)

# Fetch latest IP just in case
LATEST_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
if [ -n "$LATEST_IP" ]; then
    IP_ADDRESS="$LATEST_IP"
fi

# Clean up temp file on host
rm -f /tmp/espconnect-install.sh

header_info
echo -e "${GN}SUCCESS! ESPConnect has been installed and configured.${CL}"
echo -e "${GN}Container ID: ${CTID}${CL}"
echo -e "${GN}Access ESPConnect at: http://${IP_ADDRESS}:${RANDOM_PORT}${CL}"
echo ""
