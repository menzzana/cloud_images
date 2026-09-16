#!/bin/sh

# activate RHEL
subscription-manager register --org 4690818 --activationkey pdc

# enable CRB
subscription-manager repos --enable=codeready-builder-for-rhel-9-x86_64-rpms