#!/bin/bash
set -e  # Exit on error

# Update and install required packages
apt update
apt upgrade -y
apt install -y python3-pip python3-venv ufw wget podman

# Create a JupyterLab virtual environment
python3 -m venv /home/ubuntu/jupyter_env
source /home/ubuntu/jupyter_env/bin/activate
pip install --upgrade pip
pip install jupyterlab

# Set password for JupyterLab
JUPYTER_PASSWORD="{{password}}"

# Generate password hash
PASSWORD_HASH=$(python3 -c "from jupyter_server.auth import passwd; print(passwd('$JUPYTER_PASSWORD'))")

# Configure JupyterLab
mkdir -p /home/ubuntu/.jupyter
cat {{EOF > /home/ubuntu/.jupyter/jupyter_lab_config.py
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8080
c.ServerApp.open_browser = False
c.ServerApp.token = ''
c.ServerApp.password = '$PASSWORD_HASH'
c.ServerApp.allow_origin = '*'
EOF

# Fix permissions
chown -R ubuntu:ubuntu /home/ubuntu/.jupyter

# Create a systemd service for JupyterLab
cat {{EOF > /etc/systemd/system/jupyter.service
[Unit]
Description=Jupyter Lab for $USERNAME
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/home/ubuntu/jupyter_env/bin/jupyter-lab --config=/home/ubuntu/.jupyter/jupyter_lab_config.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Configure firewall to allow JupyterLab port
ufw allow 8080/tcp
ufw status

# Enable and start JupyterLab service
systemctl daemon-reload
systemctl enable jupyter
systemctl start jupyter

echo "JupyterLab should now be accessible at http://$(hostname -I | awk '{print $1}'):8080"
