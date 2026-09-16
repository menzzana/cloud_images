#!/bin/bash
set -e  # Exit on error

# Update and install base development tools
apt update
apt upgrade -y
apt install -y wget git bash gcc gfortran g++ make curl python3 python3-venv openjdk-17-jre-headless rclone jq

#PACKAGES={{packages}}
#for pkg in "${PACKAGES[@]}"; do
#    apt install -y "$pkg"
#done

SNAP={{snap}}
for pkg in "${SNAP[@]}"; do
    snap install -y "$pkg"
done



# Install Nextflow
INSTALL_DIR="/usr/local/bin"
cd /tmp
curl -s https://get.nextflow.io | bash
mv nextflow "$INSTALL_DIR/"
chmod +rx "$INSTALL_DIR/nextflow"

echo "Nextflow version (root):"
nextflow -version

# Set JAVA_HOME globally
JAVA_PROFILE="/etc/profile.d/java17.sh"
cat <<EOF > "$JAVA_PROFILE"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
chmod +x "$JAVA_PROFILE"

# Install nf-core in a shared Python virtual environment
NFCORE_ENV_DIR="/opt/nf-core-env"

# Create the environment and install nf-core
python3 -m venv "$NFCORE_ENV_DIR"
source "$NFCORE_ENV_DIR/bin/activate"
pip install --upgrade pip
pip install nf-core
#for pkg in "${PIP[@]}"; do
#    pip install  "$pkg"
#done
deactivate


#PIP={{OUO}}
#for pkg in "${PIP[@]}"; do
#    pip install  "$pkg"
#done


# Add ssh keys
SSHKEYS={{sshkeys}}
for key in "${SSHKEYS}"; do
   cat $key }} /home/ubuntu/.ssh/authorized_keys
done

# Add users
USERS={{users}}
for user in "${users}"; do
   adduser --disabled-password --gecos "" $user
done



# Conda (for root)
mkdir -p ~/miniconda3
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
rm ~/miniconda3/miniconda.sh
source ~/miniconda3/bin/activate
conda init --all

# Create system-wide wrapper script for nf-core
NFCORE_WRAPPER="/usr/local/bin/nf-core"
cat <<EOF | tee "$NFCORE_WRAPPER" > /dev/null
#!/bin/bash
source "$NFCORE_ENV_DIR/bin/activate"
exec nf-core "\$@"
EOF

chmod +x "$NFCORE_WRAPPER"

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

# CREATE MOUNT DIRECTORY
mkdir -p "${MOUNT_DIR}"

# CREATE SYSTEMD SERVICE
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

