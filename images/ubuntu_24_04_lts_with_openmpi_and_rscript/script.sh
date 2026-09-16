#!/bin/bash
apt update
apt upgrade -y

# development tools
apt install -y gcc git make pkg-config wget micro

# OpenMPI
apt install -y openmpi-bin openmpi-common openmpi-doc libopenmpi-dev

# GNU Scientific Library (GSL)
apt install -y libgsl-dev libgsl27

# R
apt install -y r-base r-base-dev

PACKAGES={{packages}}
for pkg in "${PACKAGES[@]}"; do
    apt install -y "$pkg"
done


RPACKAGES={{Rpackages}}
Rscript -e "install.packages('remotes')"

for rpkg in "${RPACKAGES[@]}"; do
    if [[ $rpkg = */* ]]; then
        Rscript -e "remotes::install_github('$rpkg')" 
    else
        Rscript -e "install.packages('$rpkg')"
    fi
done


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

