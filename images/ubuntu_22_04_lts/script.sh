#!/bin/bash
apt update
apt upgrade -y

PACKAGES={{packages}}
for pkg in "${PACKAGES[@]}"; do
    apt install -y "$pkg"
done
