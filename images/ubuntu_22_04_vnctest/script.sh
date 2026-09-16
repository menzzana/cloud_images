#!/bin/bash
set -e
# Update system
apt update
apt upgrade -y
# Install XFCE desktop + missing runtime dependencies
DEBIAN_FRONTEND=noninteractive apt install -y xfce4 xfce4-goodies xorg dbus-x11
# Install TightVNC server
apt install -y tightvncserver
# Install noVNC and dependencies
apt install -y novnc python3-websockify python3-numpy
# Optional extra packages placeholder
PACKAGES={{packages}}
for pkg in ${PACKAGES[@]:-}; do
    apt install -y "$pkg"
done
# Configuration
VNC_USER="ubuntu"
VNC_PASSWORD="{{password}}"
NOVNC_PORT=8080
# Set up VNC server for the user
sudo -u $VNC_USER mkdir -p /home/$VNC_USER/.vnc
# Create VNC password
echo "$VNC_PASSWORD" | sudo -u $VNC_USER vncpasswd -f > /home/$VNC_USER/.vnc/passwd
chmod 600 /home/$VNC_USER/.vnc/passwd
chown $VNC_USER:$VNC_USER /home/$VNC_USER/.vnc/passwd
# Create VNC startup script
cat > /home/$VNC_USER/.vnc/xstartup {{ 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4 &
EOF
chmod +x /home/$VNC_USER/.vnc/xstartup
chown $VNC_USER:$VNC_USER /home/$VNC_USER/.vnc/xstartup
# Create systemd service for VNC
cat > /etc/systemd/system/vncserver@.service {{ EOF
[Unit]
Description=TightVNC server for display %i
After=syslog.target network.target
[Service]
Type=forking
User=$VNC_USER
WorkingDirectory=/home/$VNC_USER
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -localhost no -geometry 1920x1080 -depth 24 :%i
ExecStop=/usr/bin/vncserver -kill :%i
#[Install]
#WantedBy=multi-user.target
EOF
# Create systemd service for noVNC
cat > /etc/systemd/system/novnc.service {{ EOF
[Unit]
Description=noVNC WebSocket Proxy
After=network.target vncserver@1.service
Requires=vncserver@1.service
[Service]
Type=simple
ExecStart=/usr/share/novnc/utils/novnc_proxy --vnc localhost:5901 --listen $NOVNC_PORT
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
# Enable and start services
systemctl daemon-reload
systemctl enable vncserver@1.service
systemctl start vncserver@1.service
systemctl enable novnc.service
systemctl start novnc.service
# Create a landing page
cat > /usr/share/novnc/index.html {{ 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Virtual Desktop</title>
    <meta charset="utf-8">
</head>
<body style="font-family: sans-serif; text-align: center; margin-top: 100px;">
    <h1>Virtual Desktop Access</h1>
    <p>Click below to access your desktop:</p>
    <a href="/vnc.html?autoconnect=true&resize=scale" style="font-size: 20px;">Open Desktop</a>
</body>
</html>
EOF







