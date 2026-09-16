#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/kcsc-bootstrap.log) 2>&1

apt update
apt upgrade -y

PACKAGES={{packages}}
for pkg in "${PACKAGES[@]}"; do
    apt install -y "$pkg"
done

ADMIN_USER="{{admin_user}}"
FQDN="{{hostname}}"
LE_EMAIL="{{letsencrypt_email}}"

# ---- The Littlest JupyterHub -------------------------------------------
curl -L https://tljh.jupyter.org/bootstrap.py | python3 - --admin "$ADMIN_USER"

# ---- Book environment, shared by all users ------------------------------
PIP=/opt/tljh/user/bin/pip
"$PIP" install --no-cache-dir nbgitpuller

SHARED=/srv/books
mkdir -p "$SHARED"
for repo in dsbook bibook; do
    git clone --depth 1 "https://github.com/statisticalbiotechnology/${repo}.git" "$SHARED/${repo}"
    "$PIP" install --no-cache-dir -r "$SHARED/${repo}/${repo}/requirements.txt"
done

# ---- HTTPS, only if a DNS name was supplied -----------------------------
TLJH_CONFIG=/opt/tljh/hub/bin/tljh-config
if [ -n "$FQDN" ] && [ -n "$LE_EMAIL" ]; then
    "$TLJH_CONFIG" set https.enabled true
    "$TLJH_CONFIG" set https.letsencrypt.email "$LE_EMAIL"
    "$TLJH_CONFIG" add-item https.letsencrypt.domains "$FQDN"
    "$TLJH_CONFIG" reload proxy
fi