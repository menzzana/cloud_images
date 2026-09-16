#!/bin/bash

# PDCLab
#
# cloud-init/pdclab-veloxchem-dev-nvgpu.sh - Cloud-init script for a Rocky 9 PDCLab VM with VeloxChem CUDA build environment  
# Author: Ilari Korhonen <ilarik@kth.se>
# Copyright (C) 2025 KTH Royal Institute of Technology


# exit on error
set -e


# PDCLab content base URL
PDCLAB_BASE_URL="https://s3.dc.pdc.kth.se/swift/v1/AUTH_b617f6725c17476383046e41a7c776a2/public/pdclab"

# PDCLab deployment URL
PDCLAB_SRC_URL="${PDCLAB_BASE_URL}/v0.1.5"

# Apptainer max session size (for overlay fs), fraction of VM mem
APPTAINER_SESSION_RAM_DIV=3

# arrays for lab user accounts from cloud portal template variable
LAB_USERS={{users.username}}
LAB_PASSWORDS={{users.password}}

# posix group of the regular user account(s)
LAB_GROUP="users"

# internal lab port (Jupyter Lab)
LAB_INT_PORT=8010

# external port for HTTP/SSL proxy
LAB_EXT_PORT=443

# PDCLab-proxy SSL certiticate and key
LAB_SSL_CERT="/etc/pki/tls/certs/localhost.crt"
LAB_SSL_KEY="/etc/pki/tls/private/localhost.key"


# =============================
# operating system preparations
# =============================

# required packages on top of rocky NVGPU image
dnf -y install apptainer httpd mod_ssl

# ASYNC: extend logical volume and root filesystem live
lvextend -r -l+100%free /dev/rocky/lvroot &

# pdclab runtime environment
for file_path in /usr/local/libexec/pdclab-nvgpu.sif{.sha256,.part0,.part1} /etc/{profile.d/pdclab.sh,sysconfig/pdclab,systemd/system/pdclab\@.service}; do
    curl ${PDCLAB_SRC_URL}${file_path} >${file_path}
done

# build pdclab container image
(cd /usr/local/libexec; cat pdclab-nvgpu.sif.part{0,1} >pdclab-nvgpu.sif)

# verify pdclab image checksum
(cd /usr/local/libexec; sha256sum -c pdclab-nvgpu.sif.sha256)

# veloxchem cuda build script
curl ${PDCLAB_BASE_URL}/bin/build-vlx-cuda.sh > /tmp/build-vlx-cuda.sh
chmod a+x /tmp/build-vlx-cuda.sh

# enable pdclab
chmod a+x /usr/local/libexec/pdclab-nvgpu.sif
systemctl daemon-reload

# configure container runtime environment
MEMTOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEMTOTAL_MB=$((${MEMTOTAL_KB} / 1024))
APPTAINER_SESSION_SIZE=$((${MEMTOTAL_MB} / ${APPTAINER_SESSION_RAM_DIV}))
sed -e "s/^sessiondir max size = [0-9]\+/sessiondir max size = ${APPTAINER_SESSION_SIZE}/" -i /etc/apptainer/apptainer.conf 

# create non-privileged user account (lab user)
useradd -g ${LAB_GROUP} ${LAB_USERS[0]}
LAB_USER_HOME=$(getent passwd ${LAB_USERS[0]} | awk -F: '{print $(NF-1)}')

# lab environment directory for lab user
LAB_ENV_BASE="${LAB_USER_HOME}/envs"
VLX_CUDA_ENV="${LAB_ENV_BASE}/vlx-cuda"

# configure pdclab runtime environment
sed -e "s#^RUNTIME_OPTS=.*#RUNTIME_OPTS=\"--writable-tmpfs --nv --env OMP_NUM_THREADS=1 --env LD_LIBRARY_PATH=${VLX_CUDA_ENV}/lib64\"#" -i /etc/sysconfig/pdclab
sed -e "s#^PDCLAB_IMG=.*#PDCLAB_IMG=\"/usr/local/libexec/pdclab-nvgpu.sif\"#" -i /etc/sysconfig/pdclab 

# ==============================
# jupyter lab user configuration
# ==============================

source /etc/profile.d/pdclab.sh

function configure_lab_user () {
    local user_name=$1
    local user_passwd=$2

    # generate password hash
    PASSWORD_HASH=$(labexec "python3 -c \"from jupyter_server.auth import passwd; print(passwd('${user_passwd}'))\"")
    
    # create jupyter config directory
    LAB_USER_HOME=$(getent passwd ${user_name} | awk -F: '{print $(NF-1)}')
    mkdir -p ${LAB_USER_HOME}/.jupyter
    
    # configure JupyterLab authentication
    cat {{EOF >${LAB_USER_HOME}/.jupyter/jupyter_lab_config.py
c.ServerApp.password = '${PASSWORD_HASH}'
c.ServerApp.allow_origin = '127.0.0.1'
EOF

    # correct permissions
    chown -R ${user_name}:${LAB_GROUP} ${LAB_USER_HOME}/.jupyter
}

configure_lab_user ${LAB_USERS[0]} ${LAB_PASSWORDS[0]}


# ============================
# build VeloxChem environment
# ============================

su - ${LAB_USERS[0]} -c "mkdir -p ${LAB_ENV_BASE}"

echo "building CUDA-enabled veloxchem into ${VLX_CUDA_ENV}..."
su - ${LAB_USERS[0]} -c "labexec /tmp/build-vlx-cuda.sh -e ${VLX_CUDA_ENV}"

echo "installing packages into ${VLX_CUDA_ENV}..."
su - ${LAB_USERS[0]} -c "labexec \"source ${VLX_CUDA_ENV}/bin/activate && pip install ipykernel\""

echo "configuring compute kernel from ${VLX_CUDA_ENV} for user ${LAB_USERS[0]}..."
su - ${LAB_USERS[0]} -c "labexec \"source ${VLX_CUDA_ENV}/bin/activate && python -m ipykernel install --user --name 'VeloxChem-NVIDIA-GPU'\""


# =================================================================
# HTTP/SSL proxy build (TODO: move all into pdclab-proxy container)
# =================================================================

mv /etc/httpd/conf.d/ssl.conf{,.dist}
cat >/etc/httpd/conf.d/ssl.conf {{EOF
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
systemctl enable pdclab@${LAB_USERS[0]}.service

# SYNC: wait for packages update and conda env builds
wait


# ==============
# start services
# ==============

# ASYNC: start services in parallel
systemctl start httpd.service &
systemctl start pdclab@${LAB_USERS[0]}.service &

# SYNC: wait for services to start
wait
