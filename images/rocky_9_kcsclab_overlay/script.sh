#!/bin/bash

# PDCLab
#
# cloud-init/pdclab-rocky-envs-overlay.sh - Cloud-init script for a Rocky 9 PDCLab VM with overlay environments
# Author: Ilari Korhonen <ilarik@kth.se>
# Copyright (C) 2025 KTH Royal Institute of Technology


# exit on error
set -e


# PDCLab content base URL
PDCLAB_BASE_URL="https://s3.dc.pdc.kth.se/swift/v1/AUTH_b617f6725c17476383046e41a7c776a2/public/pdclab"

# PDCLab deployment URL
PDCLAB_SRC_URL="${PDCLAB_BASE_URL}/v0.1.5"

# PDCLab conda envs URL
PDCLAB_CONDA_URL="${PDCLAB_BASE_URL}/envs/conda"

# Apptainer max session size (for overlay fs), fraction of VM mem
APPTAINER_SESSION_RAM_DIV=3

# arrays for lab user accounts from cloud portal template variable
LAB_USERS={{users.username}}
LAB_PASSWORDS={{users.password}}

# posix group of the regular user account(s)
LAB_GROUP="users"

# base path for lab environments
LAB_ENV_BASE="/opt/envs"

# base path for lab environment overlay fs images
LAB_ENV_IMG_BASE="/usr/local/share/pdclab/overlays"

# internal lab port (Jupyter Lab)
LAB_INT_PORT=8010

# external port for HTTP/SSL proxy
LAB_EXT_PORT=443

# PDCLab-proxy SSL certiticate and key
LAB_SSL_CERT="/etc/pki/tls/certs/localhost.crt"
LAB_SSL_KEY="/etc/pki/tls/private/localhost.key"

# shared object storage (project-wide)
APP_CRED_ID="{{cred_id}}"
APP_CRED_SECRET="{{cred_secret}}"
OS_AUTH_URL="{{cloud_url}}/v3"
OS_PROJECT_NAME="{{project_name}}"
OS_USER_DOMAIN_NAME="{{cloud_domain}}"
OS_PROJECT_DOMAIN_NAME="{{project_domain}}"
CONTAINER_NAME="{{project_data}}"
MOUNT_DIR="/mnt/${CONTAINER_NAME}"


# =============================
# operating system preparations
# =============================

# extend logical volume and root filesystem live
lvextend -r -l+100%free /dev/rocky/lvroot

# pdclab runtime environment
for file_path in /usr/local/libexec/pdclab.sif{,.sha256} /etc/{profile.d/pdclab.sh,sysconfig/pdclab,systemd/system/pdclab\@.service}; do
    curl ${PDCLAB_SRC_URL}${file_path} >${file_path}
done

# verify pdclab image checksum
(cd /usr/local/libexec; sha256sum -c pdclab.sif.sha256)

# enable pdclab
chmod a+x /usr/local/libexec/pdclab.sif
systemctl daemon-reload

# configure container runtime environment
MEMTOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEMTOTAL_MB=$((${MEMTOTAL_KB} / 1024))
APPTAINER_SESSION_SIZE=$((${MEMTOTAL_MB} / ${APPTAINER_SESSION_RAM_DIV}))
sed -e "s/^sessiondir max size = [0-9]\+/sessiondir max size = ${APPTAINER_SESSION_SIZE}/" -i /etc/apptainer/apptainer.conf 

# configure rclone for object storage
mkdir -p /root/.config/rclone
cat > /root/.config/rclone/rclone.conf <<EOF
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


# ======================================
# jupyter lab user configuration (ASYNC)
# ======================================

source /etc/profile.d/pdclab.sh

function configure_lab_user () {
    local user_name=$1
    local user_passwd=$2

    # create non-privileged user account (lab user)
    useradd -g ${LAB_GROUP} ${user_name}

    # generate password hash
    PASSWORD_HASH=$(labexec "python3 -c \"from jupyter_server.auth import passwd; print(passwd('${user_passwd}'))\"")

    # create jupyter config directory
    LAB_USER_HOME=$(getent passwd ${user_name} | awk -F: '{print $(NF-1)}')
    mkdir -p ${LAB_USER_HOME}/.jupyter

    # configure JupyterLab authentication
    cat <<EOF >${LAB_USER_HOME}/.jupyter/jupyter_lab_config.py
c.ServerApp.password = '${PASSWORD_HASH}'
c.ServerApp.allow_origin = '127.0.0.1'
EOF

    # correct permissions
    chown -R ${user_name}:${LAB_GROUP} ${LAB_USER_HOME}/.jupyter
}

configure_lab_user ${LAB_USERS[0]} ${LAB_PASSWORDS[0]}


# ================================
# rclone fuse mount configuaration
# ================================

# create systemd service
SERVICE_FILE="/etc/systemd/system/rclone-swift.service"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Rclone mount for OpenStack Swift storage
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount swift:${CONTAINER_NAME} ${MOUNT_DIR} \\
    --allow-other \\
    --uid $(id -u ${LAB_USERS[0]}) \\
    --gid $(id -g ${LAB_USERS[0]}) \\
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

sed -e "s/^RUNTIME_OPTS=.*/RUNTIME_OPTS=\"--writable-tmpfs --mount type=bind,src=$(echo ${MOUNT_DIR} | sed 's#\/#\\\/#g'),dst=$(echo ${MOUNT_DIR} | sed 's#\/#\\\/#g')\"/" -i /etc/sysconfig/pdclab

mkdir -p ${MOUNT_DIR}
su - ${LAB_USERS[0]} -c "ln -s ${MOUNT_DIR} ~/${CONTAINER_NAME}"

systemctl daemon-reload


# =====================================
# install conda environments (ASYNC)
# =====================================

mkdir -p ${LAB_ENV_IMG_BASE}

readarray conda_envs_raw < <(curl -s ${PDCLAB_CONDA_URL}/MANIFEST | egrep "^[a-zA-Z]")

declare -A conda_env_spec
declare -A conda_env_img

for ((i = 0; i < ${#conda_envs_raw[@]}; i++)); do
    read -a conda_env < <(echo ${conda_envs_raw[$i]})

    conda_env_spec[${conda_env[0]}]=${conda_env[1]}
    conda_env_img[${conda_env[0]}]=${conda_env[2]}
done

function install_conda_env() {
    local env_name=$1
    local env_img_path=$2

    echo "installing conda environment: ${env_name} (${env_img_path})..."

    for remote_path in ${env_img_path}{,.sha256}; do
        file_name=$(basename ${remote_path})
        curl ${PDCLAB_CONDA_URL}/${remote_path} >${LAB_ENV_IMG_BASE}/${file_name}
    done

    local env_img_sha256_file="$(basename ${env_img_path}).sha256"
    (cd ${LAB_ENV_IMG_BASE}; sha256sum -c ${env_img_sha256_file})
}

for env_name in ${!conda_env_img[@]}; do
    env_img=${conda_env_img[$env_name]}
    install_conda_env ${env_name} ${env_img} &
done


# =================================================================
# HTTP/SSL proxy build (TODO: move all into pdclab-proxy container)
# =================================================================

mv /etc/httpd/conf.d/ssl.conf{,.dist}
cat >/etc/httpd/conf.d/ssl.conf <<EOF
Listen 443 https

SSLPassPhraseDialog exec:/usr/libexec/httpd-ssl-pass-dialog
SSLSessionCache         shmcb:/run/httpd/sslcache(512000)
SSLSessionCacheTimeout  300
SSLCryptoDevice builtin

<VirtualHost _default_:443>
ErrorLog logs/ssl_error_log
TransferLog logs/ssl_access_log
LogLevel warn
CustomLog logs/ssl_request_log \
          "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \"%r\" %b"

SSLEngine on
SSLHonorCipherOrder on
SSLCipherSuite PROFILE=SYSTEM
SSLProxyCipherSuite PROFILE=SYSTEM
SSLCertificateFile /etc/pki/tls/certs/localhost.crt
SSLCertificateKeyFile /etc/pki/tls/private/localhost.key

BrowserMatch "MSIE [2-5]" \
         nokeepalive ssl-unclean-shutdown \
         downgrade-1.0 force-response-1.0

RequestHeader set Origin "http://localhost:8010"
RequestHeader set Referer "http://localhost:8010"

AllowEncodedSlashes On
RewriteEngine On

ProxyPass / http://localhost:8010/
ProxyPassReverse / http://localhost:8010/

ProxyPass /api ws://localhost:8010/api/
ProxyPassReverse /api ws://localhost:8010/api/

RewriteCond %{HTTP:Connection} Upgrade [NC]
RewriteCond %{HTTP:Upgrade} websocket [NC]
RewriteRule /api/(.*) ws://localhost:8010/api/\$1 [P,L]

RewriteCond %{HTTP:Connection} Upgrade [NC]
RewriteCond %{HTTP:Upgrade} websocket [NC]
RewriteRule /terminals/websocket/(.*) ws://localhost:8010/terminals/websocket/\$1 [P,L]

RewriteCond %{HTTP:Connection} Upgrade [NC]
RewriteCond %{HTTP:Upgrade} websocket [NC]
RewriteRule /desktop/(.*) ws://localhost:8010/desktop/\$1 [P,L]

RewriteCond %{HTTP:Connection} Upgrade [NC]
RewriteCond %{HTTP:Upgrade} websocket [NC]
RewriteRule /desktop-websockify/(.*) ws://localhost:8010/desktop-websockify/\$1 [P,L]
</VirtualHost>
EOF


# ==========================
# final system configuration
# ==========================

# configure SELinux for httpd proxy
setsebool -P httpd_can_network_relay=1
setsebool -P httpd_can_network_connect=1

# enable services
systemctl enable httpd.service
systemctl enable rclone-swift.service
systemctl enable pdclab@${LAB_USERS[0]}.service


# SYNC: wait for packages update and conda env builds
wait


# =====================================================
# configure overlay filesystems and activate conda envs
# =====================================================

OVERLAY_ARGS=""

for overlay_img in ${conda_env_img[@]}; do
    img_file=$(basename $overlay_img)
    OVERLAY_ARGS+="--overlay ${LAB_ENV_IMG_BASE}/${img_file} "
done

sed -e "s|^OVERLAY_ARGS=\".*\"|OVERLAY_ARGS=\"$OVERLAY_ARGS\"|" -i /etc/sysconfig/pdclab
source /etc/sysconfig/pdclab

for conda_env in ${!conda_env_spec[@]}; do
    env_file=${conda_env_spec[${conda_env}]}
    env_dir=${env_file%%.yml}
    
    su - ${LAB_USERS[0]} -c "labexec condaenv ${LAB_ENV_BASE}/${env_dir} python -m ipykernel install --user --name=${conda_env}" &
done


# ==============
# start services
# ==============

# ASYNC: start services in parallel
systemctl start httpd.service &
systemctl start rclone-swift.service &
systemctl start pdclab@${LAB_USERS[0]}.service &

# SYNC: wait for services to start
wait
