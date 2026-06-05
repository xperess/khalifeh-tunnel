#!/bin/bash
# Khalifeh Tunnel - Installer

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "========================================="
echo "   Khalifeh Tunnel - Installation"
echo "========================================="
echo ""

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Error: Please run as root (sudo bash install.sh)${NC}"
    exit 1
fi

# Create directory
mkdir -p /opt/khalifeh
mkdir -p /opt/khalifeh/profiles
mkdir -p /opt/khalifeh/logs

# Download files
echo "[*] Downloading files..."
REPO_URL="https://raw.githubusercontent.com/xperess/khalifeh-tunnel/main"

curl -s -o /opt/khalifeh/khalifeh.py "$REPO_URL/khalifeh.py"
curl -s -o /opt/khalifeh/manager.sh "$REPO_URL/manager.sh"

chmod +x /opt/khalifeh/khalifeh.py
chmod +x /opt/khalifeh/manager.sh

# Fix line endings
sed -i 's/\r$//' /opt/khalifeh/khalifeh.py
sed -i 's/\r$//' /opt/khalifeh/manager.sh

# Create symlink
ln -sf /opt/khalifeh/manager.sh /usr/local/bin/khalifeh

# Install dependencies
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y python3 screen iproute2 >/dev/null 2>&1

# Increase file limits
echo "root soft nofile 65535" >> /etc/security/limits.conf
echo "root hard nofile 65535" >> /etc/security/limits.conf

# Create default profile for Iran
mkdir -p /opt/khalifeh/profiles
cat > /opt/khalifeh/profiles/iran_default.conf << 'EOF'
name=Iran Default
mode=server
bridge_port=7000
sync_port=7001
auto_sync=false
ports=37899,38455,34538,51873,58318
exclude_ports=22,53,80,443,2096,9876,11111
EOF

cat > /opt/khalifeh/profiles/eu_default.conf << 'EOF'
name=EU Default
mode=client
iran_ip=CHANGE_ME
bridge_port=7000
sync_port=7001
exclude_ports=22,53,80,443,2096,9876,11111
EOF

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Run: sudo khalifeh"
echo ""