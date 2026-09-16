#!/bin/bash

set -e

# Function to fetch the latest stable GROMACS version
get_latest_version() {
    ver=$(wget -qO- "https://ftp.gromacs.org/gromacs/" 2>/dev/null \
        | grep -oE 'gromacs-[0-9]+(\.[0-9]+){1,2}\.tar\.gz' \
        | sed -E 's/^gromacs-//; s/\.tar\.gz$//' \
        | sort -V \
        | tail -n1 || true)
    if [ -n "$ver" ]; then
        printf '%s\n' "$ver"
        return 0
    fi
    echo "ERROR: could not determine latest GROMACS version" >&2
    return 1
}

# Fetch or set version
GROMACS_VERSION="{{version}}"
if [ "$GROMACS_VERSION" = "latest" ]; then
    GROMACS_VERSION=$(get_latest_version)
fi
echo "GROMACS version: $GROMACS_VERSION"

# Update and install dependencies
apt update
apt upgrade -y

PACKAGES={{packages}}
for pkg in "${PACKAGES[@]}"; do
    apt install -y "$pkg"
done

# Download GROMACS source
wget https://ftp.gromacs.org/gromacs/gromacs-${GROMACS_VERSION}.tar.gz
tar xfz gromacs-${GROMACS_VERSION}.tar.gz
cd gromacs-${GROMACS_VERSION}

# Create build directory
mkdir build && cd build

# Configure with CMake
cmake .. -DGMX_BUILD_OWN_FFTW=ON -DREGRESSIONTEST_DOWNLOAD=ON -DCMAKE_INSTALL_PREFIX=/usr/local/gromacs

# Compile (use all CPU cores)
make -j$(nproc)

# Install
sudo make install

# Source GROMACS environment
echo "source /usr/local/gromacs/bin/GMXRC" | tee /etc/profile.d/gromacs.sh
chmod +x /etc/profile.d/gromacs.sh

# Verify installation
gmx --version

echo "GROMACS ${GROMACS_VERSION} installation completed!"