#!/bin/bash
# Update the system
apt-get update -y
apt-get upgrade -y

# Add the focal-security repository
apt-add-repository -y 'deb http://security.ubuntu.com/ubuntu focal-security main'
apt-get update

# Install dependencies
apt-get install -y wget git bash gcc gfortran g++ make gdebi-core software-properties-common dirmngr libssl1.1 r-base

# Install extra R packages
R_PACKAGES={{Rpackages}}

if [ -n "$R_PACKAGES" ]; then
    # Convert packages array to a comma-separated R vector and install
    Rscript -e "packages <- c($(printf '"%s",' "${R_PACKAGES[@]}" | sed 's/,$//'));
    installed <- rownames(installed.packages());
    for (p in packages) {
        if (!(p %in% installed)) {
            install.packages(p, repos='https://cloud.r-project.org')
        }
    }"
fi

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
wget https://download2.rstudio.org/server/jammy/amd64/rstudio-server-{{version}}-amd64.deb -O /tmp/rstudio-server.deb

gdebi -n /tmp/rstudio-server.deb

# Configure RStudio Server
mkdir -p /etc/rstudio
cat > /etc/rstudio/rserver.conf {{'EOF'
www-address=0.0.0.0
www-port=8787
EOF

# THE ONLY THING REQUIRED FOR AUTOSTART
systemctl daemon-reload
systemctl enable rstudio-server
systemctl restart rstudio-server
