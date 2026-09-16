#!/bin/bash

# Apache CGI Setup Script for Ubuntu
# This script installs Apache, enables CGI, and sets up basic configuration

set -e  # Exit on any error

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
    jq \
    apache2 \
    apache2-utils


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

echo "Enabling CGI module..."
a2enmod cgi

echo "Enabling rewrite module (useful for web development)..."
a2enmod rewrite

echo "Starting and enabling Apache service..."
systemctl start apache2
systemctl enable apache2

echo "Setting up CGI directory permissions..."
# The default cgi-bin directory is /usr/lib/cgi-bin/
chmod 755 /usr/lib/cgi-bin/

echo "Creating a test CGI script..."
tee /usr/lib/cgi-bin/test.cgi > /dev/null {{'EOF'
#!/bin/bash
echo "Content-Type: text/html"
echo ""
echo "<html><head><title>CGI Test</title></head><body>"
echo "<h1>CGI Script Working!</h1>"
echo "<p>Current date and time: $(date)</p>"
echo "<p>Server: $(hostname)</p>"
echo "</body></html>"
EOF

echo "Making test CGI script executable..."
chmod +x /usr/lib/cgi-bin/test.cgi

echo "Creating a simple HTML test page..."
tee /var/www/html/index.html > /dev/null {{'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Apache CGI Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .success { color: green; }
        .info { background: #f0f0f0; padding: 15px; border-radius: 5px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Apache CGI Server Setup Complete!</h1>
        <p class="success">Your Apache server with CGI support is now running.</p>
        
        <div class="info">
            <h3>Quick Test:</h3>
            <p><a href="/cgi-bin/test.cgi">Click here to test your CGI setup</a></p>
        </div>
        
        <div class="info">
            <h3>Important Directories:</h3>
            <ul>
                <li><strong>Web Root:</strong> /var/www/html/</li>
                <li><strong>CGI Scripts:</strong> /usr/lib/cgi-bin/</li>
                <li><strong>Apache Config:</strong> /etc/apache2/</li>
                <li><strong>Apache Logs:</strong> /var/log/apache2/</li>
            </ul>
        </div>
        
        <div class="info">
            <h3>Quick Commands:</h3>
            <ul>
                <li>Restart Apache: <code>sudo systemctl restart apache2</code></li>
                <li>Check Status: <code>sudo systemctl status apache2</code></li>
                <li>View Error Logs: <code>sudo tail -f /var/log/apache2/error.log</code></li>
                <li>View Access Logs: <code>sudo tail -f /var/log/apache2/access.log</code></li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

echo "Restarting Apache to apply all changes..."
systemctl restart apache2

echo "Checking Apache status..."
if systemctl is-active --quiet apache2; then
    echo "Apache is running successfully!"
else
    echo "Apache failed to start. Check logs with: sudo journalctl -u apache2"
    exit 1
fi

# Check if firewall is active and provide guidance
if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    echo "Firewall (ufw) is active. You may need to allow HTTP traffic:"
    echo "sudo ufw allow 'Apache'"
    echo "sudo ufw allow 'Apache Full'  # For both HTTP and HTTPS"
fi

echo "Setup completed successfully!"
