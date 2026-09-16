#!/bin/sh

USER_PACKAGES={{packages}}


# add 16G to root fs
lvextend -r -L+16G /dev/rocky/lvroot

# configure NVIDIA grid daemon for vGPU
sed -e 's/^FeatureType=*./FeatureType=1/' -i /etc/nvidia/gridd.conf

# install requested packages
dnf install -y "${USER_PACKAGES[@]}"
