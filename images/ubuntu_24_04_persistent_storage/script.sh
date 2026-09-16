#!/bin/bash
apt update
apt upgrade -y
apt install -y rclone jq

PACKAGES={{packages}}
for pkg in "${PACKAGES[@]}"; do
    apt install -y "$pkg"
done

# CONFIGURATION
APP_CRED_ID="{{cred_id}}"
APP_CRED_SECRET="{{cred_secret}}"
OS_AUTH_URL="{{cloud_url}}/v3"
OS_PROJECT_NAME="{{project_name}}"
OS_USER_DOMAIN_NAME="{{cloud_domain}}"
OS_PROJECT_DOMAIN_NAME="{{project_domain}}"
CONTAINER_NAME="{{project_data}}"
MOUNT_DIR="/mnt/${CONTAINER_NAME}"

# CREATE RCLONE CONFIG
mkdir -p /root/.config/rclone
cat > /root/.config/rclone/rclone.conf {{EOF
[swift]
type = swift
auth = ${OS_AUTH_URL}
domain = ${OS_USER_DOMAIN_NAME}
tenant = ${OS_PROJECT_NAME}
tenant_domain = ${OS_PROJECT_DOMAIN_NAME}
application_credential_id = ${APP_CRED_ID}
application_credential_secret = ${APP_CRED_SECRET}
env_auth = false
EOF

# CREATE MOUNT DIRECTORY
mkdir -p "${MOUNT_DIR}"

# CREATE SYSTEMD SERVICE
SERVICE_FILE="/etc/systemd/system/rclone-swift.service"

cat > "${SERVICE_FILE}" {{EOF
[Unit]
Description=Rclone mount for OpenStack Swift storage
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount swift:${CONTAINER_NAME} ${MOUNT_DIR} \\
    --allow-other \\
    --uid 1000 \\
    --gid 1000 \\
    --vfs-cache-mode full \\
    --vfs-cache-max-age 24h \\
    --vfs-cache-max-size 10G \\
    --buffer-size 256M \\
    --log-file /var/log/rclone-swift.log \\
    --config /root/.config/rclone/rclone.conf
ExecStop=/bin/fusermount -u ${MOUNT_DIR}
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# ENABLE AND START THE SERVICE
systemctl daemon-reload
systemctl enable rclone-swift.service
systemctl start rclone-swift.service
