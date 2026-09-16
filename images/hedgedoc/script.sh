#!/bin/bash
set -e

# Install Docker
echo "Installing Docker..."
apt update
apt install -y ca-certificates curl gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
echo "Docker installed successfully."

# Pull images
echo "Pulling Docker images..."
docker pull postgres:13
docker pull quay.io/hedgedoc/hedgedoc:latest

# Create Docker network
echo "Creating Docker network..."
docker network create hedgedoc-network 2>/dev/null || true

# Create volumes
echo "Creating Docker volumes..."
docker volume create hedgedoc-data
docker volume create hedgedoc-postgres-data

# Generate and store passwords for consistent use
DB_PASSWORD="hedgedoc_secure_password_$(openssl rand -hex 8)"
SESSION_SECRET=$(openssl rand -hex 32)

# Store passwords for later use by update script
echo "$DB_PASSWORD" > /opt/hedgedoc-db-password
echo "$SESSION_SECRET" > /opt/hedgedoc-session-secret
chmod 600 /opt/hedgedoc-db-password /opt/hedgedoc-session-secret

echo "Generated database password: $DB_PASSWORD"

# Start PostgreSQL container
echo "Starting PostgreSQL container..."
docker run -d \
  --name hedgedoc-postgres \
  --network hedgedoc-network \
  -e POSTGRES_DB=hedgedoc \
  -e POSTGRES_USER=hedgedoc \
  -e POSTGRES_PASSWORD="$DB_PASSWORD" \
  -v hedgedoc-postgres-data:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:13

# Create startup script for IP updates (runs on boot)
STARTUP_SCRIPT=/opt/hedgedoc-ip-update.sh
cat > $STARTUP_SCRIPT << 'EOF'
#!/bin/bash

echo "Waiting for Docker daemon..."
for i in {1..30}; do
    if docker info > /dev/null 2>&1; then
        echo "Docker is ready"
        break
    fi
    sleep 2
done

echo "Waiting for PostgreSQL to accept connections..."
for i in {1..60}; do
    if docker exec hedgedoc-postgres pg_isready -U hedgedoc > /dev/null 2>&1; then
        echo "Postgres is ready"
        break
    fi
    sleep 5
done

# Function to get public IP
get_public_ip() {
    PUBLIC_IP=$(curl -s --connect-timeout 10 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || \
                curl -s --connect-timeout 10 http://checkip.amazonaws.com/ 2>/dev/null || \
                curl -s --connect-timeout 10 https://ipinfo.io/ip 2>/dev/null || \
                curl -s --connect-timeout 10 https://api.ipify.org 2>/dev/null)
    
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP=$(hostname -I | awk '{print $1}')
    fi
    
    echo "$PUBLIC_IP"
}

# Get current IP
CURRENT_IP=$(get_public_ip)    
# Read stored passwords
DB_PASSWORD=$(cat /opt/hedgedoc-db-password)
SESSION_SECRET=$(cat /opt/hedgedoc-session-secret)

# Store current IP
echo "$CURRENT_IP" > /var/log/hedgedoc-current-ip
if [ -z "$CURRENT_IP" ]; then
    echo "$(date): No public IP detected, exiting with failure"
    exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -q '^hedgedoc$'; then
  docker stop hedgedoc 2>/dev/null || true
  docker rm hedgedoc 2>/dev/null || true
fi

# Start HedgeDoc with the EXACT configuration that made it fast
docker run -d \
  --name hedgedoc \
  --network hedgedoc-network \
  -p 8080:3000 \
  -v hedgedoc-data:/hedgedoc/public/uploads \
  -e CMD_DB_DIALECT=postgres \
  -e CMD_DB_HOST=hedgedoc-postgres \
  -e CMD_DB_PORT=5432 \
  -e CMD_DB_DATABASE=hedgedoc \
  -e CMD_DB_USERNAME=hedgedoc \
  -e CMD_DB_PASSWORD="$DB_PASSWORD" \
  -e CMD_DOMAIN="$CURRENT_IP:8080" \
  -e CMD_HOST=0.0.0.0 \
  -e CMD_PORT=3000 \
  -e CMD_URL_ADDPORT=false \
  -e CMD_PROTOCOL_USESSL=false \
  -e CMD_ALLOW_ORIGIN="$CURRENT_IP:8080,localhost:8080" \
  -e CMD_SESSION_SECRET="$SESSION_SECRET" \
  -e NODE_OPTIONS="--max-old-space-size=2048" \
  -e CMD_LOGLEVEL=info \
  -e CMD_ALLOW_GRAVATAR=false \
  -e CMD_DEFAULT_PERMISSION=freely \
  -e CMD_ALLOW_ANONYMOUS=true \
  -e CMD_ALLOW_ANONYMOUS_EDITS=true \
  -e CMD_CSP_ENABLE=false \
  --restart unless-stopped \
  --memory=2g \
  --cpus=2.0 \
  quay.io/hedgedoc/hedgedoc:latest

EOF

chmod +x $STARTUP_SCRIPT

# Create systemd service for IP updates
SERVICE_FILE=/etc/systemd/system/hedgedoc-ip-update.service
cat > $SERVICE_FILE << EOF
[Unit]
Description=HedgeDoc IP Update Service
After=network-online.target docker.service systemd-resolved.service
Wants=network-online.target systemd-networkd-wait-online.service
Requires=docker.service network-online.target

[Service]
Type=simple
ExecStart=/opt/hedgedoc-ip-update.sh
Restart=on-failure
RestartSec=30
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable IP update service
systemctl daemon-reload
systemctl enable hedgedoc-ip-update.service

# Configure firewall
if command -v ufw > /dev/null 2>&1; then
    echo "Configuring firewall..."
    ufw allow 8080/tcp
fi

echo "Installation complete! The system will reboot to start HedgeDoc."

reboot
