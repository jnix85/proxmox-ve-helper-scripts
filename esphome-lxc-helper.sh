#!/usr/bin/env bash

# This script creates a Proxmox LXC container running ESPHome.
# It is designed to look and feel like scripts from https://helper-scripts.com (tteck)
# This custom version runs without SSL and terminates on a random port.

# Create an install script to run inside the LXC
cat << 'EOF' > /tmp/esphome-install.sh
#!/usr/bin/env bash

# Exported from host environment: RAND_PORT
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl sudo mc git
msg_ok "Installed Dependencies"

msg_info "Updating Python3"
$STD apt-get install -y python3 python3-dev python3-pip python3-venv
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
msg_ok "Updated Python3"

msg_info "Installing ESPHome"
mkdir -p /root/config
$STD pip install esphome tornado esptool
msg_ok "Installed ESPHome"

msg_info "Creating Service on port $RAND_PORT without SSL"
cat <<SERVICE >/etc/systemd/system/esphomeDashboard.service
[Unit]
Description=ESPHome Dashboard
After=network.target

[Service]
ExecStart=/usr/local/bin/esphome dashboard /root/config/ --port $RAND_PORT
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE
systemctl enable -q --now esphomeDashboard.service
msg_ok "Created Service (Port: $RAND_PORT)"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
EOF

# Download and patch build.func to use our custom install script
wget -qO /tmp/build.func https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func
sed -i 's|lxc-attach -n "$CTID" -- bash -c "$(wget -qLO - https://raw.githubusercontent.com/tteck/Proxmox/main/install/$var_install.sh)"|lxc-attach -n "$CTID" -- bash -c "$(cat /tmp/esphome-install.sh)"|g' /tmp/build.func

# Source the patched build.func
source /tmp/build.func

function header_info {
clear
cat <<"EOF"
    ___________ ____  __  __                   
   / ____/ ___// __ \/ / / /___  ____ ___  ___ 
  / __/  \__ \/ /_/ / /_/ / __ \/ __ `__ \/ _ \
 / /___ ___/ / ____/ __  / /_/ / / / / / /  __/
/_____//____/_/   /_/ /_/\____/_/ /_/ /_/\___/ 
                                               
EOF
}

header_info
echo -e "Loading..."
APP="ESPHome"
var_disk="4"
var_cpu="2"
var_ram="1024"
var_os="debian"
var_version="12"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

export RAND_PORT=$((RANDOM % 50000 + 10000))

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL."
echo -e "         ${BL}http://${IP}:${RAND_PORT}${CL} \n"

# Clean up temporary files
rm /tmp/esphome-install.sh /tmp/build.func
