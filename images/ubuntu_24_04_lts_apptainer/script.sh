#!/bin/bash
set -e  # Exit on error

# Update system packages
apt update
apt upgrade -y

# Install required dependencies
apt install -y \
    build-essential \
    libseccomp-dev \
    pkg-config \
    squashfs-tools \
    cryptsetup \
    curl \
    git \
    uidmap \
    jq

# Fetch the latest Apptainer release version from GitHub
LATEST_VERSION=$(curl -s https://api.github.com/repos/apptainer/apptainer/releases/latest | jq -r .tag_name)

# Remove the 'v' prefix from the version tag if present
VERSION=${LATEST_VERSION#v}

# Download the corresponding .deb package
cd /tmp
curl -LO https://github.com/apptainer/apptainer/releases/download/${LATEST_VERSION}/apptainer_${VERSION}_amd64.deb

# Install the package
apt install -y ./apptainer_${VERSION}_amd64.deb

# Clean up
rm ./apptainer_${VERSION}_amd64.deb

# Verify installation
apptainer --version

echo "Apptainer ${VERSION} installed successfully."
