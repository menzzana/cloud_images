#!/bin/bash
# Update the system
apt-get update -y
apt-get upgrade -y

# Add the focal-security repository
apt-add-repository -y 'deb http://security.ubuntu.com/ubuntu focal-security main'
apt-get update

# Install dependencies
APT_PACKAGES={{packages}}
apt-get install -y wget git bash gcc gfortran g++ make gdebi-core software-properties-common dirmngr libssl1.1 r-base ${APT_PACKAGES[@]}

# Install extra R packages
R_PACKAGES={{Rpackages}}

# Convert packages array to a comma-separated R vector and install
Rscript -e "packages <- c($(printf '"%s",' "${R_PACKAGES[@]}" | sed 's/,$//'));
installed <- rownames(installed.packages());
for (p in packages) {
    if (!(p %in% installed)) {
        install.packages(p, repos='https://cloud.r-project.org')
    }
}"

# Create user account with explicit password
USERNAMES={{users.username}}
PASSWORDS={{users.password}}

for i in "${!USERNAMES[@]}"; do
    # Create user
    useradd -m -s /bin/bash "${USERNAMES[$i]}"

    # Set password
    echo "${USERNAMES[$i]}:${PASSWORDS[$i]}" | chpasswd

    # Home directory and has correct permissions
    mkdir -p "/home/${USERNAMES[$i]}"
    chown -R "${USERNAMES[$i]}":"${USERNAMES[$i]}" "/home/${USERNAMES[$i]}"
done

# Download and install RStudio Server
if [ "{{version}}" = "latest" ]; then
    wget https://rstudio.org/download/latest/stable/server/focal/rstudio-server-latest-amd64.deb -O /tmp/rstudio-server.deb
else
    wget https://download2.rstudio.org/server/focal/amd64/rstudio-server-{{version}}-amd64.deb -O /tmp/rstudio-server.deb
fi

gdebi -n /tmp/rstudio-server.deb

# Create RStudio Server configuration directory if it doesn't exist
mkdir -p /etc/rstudio

# Configure RStudio Server to listen on all network interfaces
echo "www-address=0.0.0.0" > /etc/rstudio/rserver.conf
echo "www-port=8787" }} /etc/rstudio/rserver.conf

# Create RStudio Server service file
# Modify your image_script to include these improvements:

# 1. Add proper dependencies in your systemd service
echo '[Unit]
Description=RStudio Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/lib/rstudio-server/bin/rserver
Restart=on-failure
RestartSec=10
User=rstudio
Group=rstudio
WorkingDirectory=/home/rstudio

[Install]
WantedBy=multi-user.target' > /etc/systemd/system/rstudio-server.service

# 2. Add a delay and restart after system boot
cat <<EOF > /etc/systemd/system/rstudio-restart.service
[Unit]
Description=Restart RStudio Server after network stabilization
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "sleep 30 && systemctl restart rstudio-server"

[Install]
WantedBy=multi-user.target
EOF

systemctl enable rstudio-restart.service

