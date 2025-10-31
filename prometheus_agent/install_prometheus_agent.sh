#!/bin/bash

# Prometheus Agent Installation Script
# Installs Prometheus in agent mode on the same host as prtg_exporter
# Based on: https://prometheus.io/download/ and https://prometheus.io/blog/2021/11/16/agent/

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Prometheus Agent Installation Script${NC}"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Configuration
# Get latest Prometheus version or use specific version
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-2.48.0}"  # Default to 2.48.0, can be overridden
ARCH="amd64"
PROMETHEUS_DIR="/etc/prometheus"
DATA_DIR="/var/lib/prometheus"
CONFIG_FILE="$PROMETHEUS_DIR/prometheus.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Step 1: Download Prometheus Linux tarball
echo -e "\n${YELLOW}Step 1: Downloading Prometheus...${NC}"
cd /tmp
PROMETHEUS_TARBALL="prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
PROMETHEUS_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_TARBALL}"

if [ -f "$PROMETHEUS_TARBALL" ]; then
    echo "Tarball already exists, skipping download"
else
    echo "Downloading Prometheus ${PROMETHEUS_VERSION}..."
    curl -L -o "$PROMETHEUS_TARBALL" "$PROMETHEUS_URL" || {
        echo -e "${RED}Error: Failed to download Prometheus${NC}"
        echo "Trying to fetch latest version..."
        # Try to get latest version from GitHub API
        LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')
        if [ -n "$LATEST_VERSION" ]; then
            PROMETHEUS_VERSION="$LATEST_VERSION"
            PROMETHEUS_TARBALL="prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
            PROMETHEUS_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_TARBALL}"
            echo "Downloading latest version: ${PROMETHEUS_VERSION}..."
            curl -L -o "$PROMETHEUS_TARBALL" "$PROMETHEUS_URL" || {
                echo -e "${RED}Error: Failed to download Prometheus${NC}"
                exit 1
            }
        else
            exit 1
        fi
    }
fi

# Step 2: Extract and install binaries
echo -e "\n${YELLOW}Step 2: Extracting and installing Prometheus binaries...${NC}"
tar -xzf "$PROMETHEUS_TARBALL"
# Find the extracted directory (in case version format differs)
PROMETHEUS_EXTRACTED_DIR=$(find /tmp -maxdepth 1 -type d -name "prometheus-*linux-${ARCH}" | head -1)
if [ -z "$PROMETHEUS_EXTRACTED_DIR" ]; then
    echo -e "${RED}Error: Could not find extracted Prometheus directory${NC}"
    exit 1
fi
echo "Found extracted directory: $PROMETHEUS_EXTRACTED_DIR"

# Create directories
echo "Creating directories..."
mkdir -p "$PROMETHEUS_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/agent"

# Install binaries
echo "Installing prometheus and promtool binaries..."
cp "$PROMETHEUS_EXTRACTED_DIR/prometheus" /usr/local/bin/
cp "$PROMETHEUS_EXTRACTED_DIR/promtool" /usr/local/bin/
chmod +x /usr/local/bin/prometheus
chmod +x /usr/local/bin/promtool

# Verify installation
if ! command -v prometheus &> /dev/null; then
    echo -e "${RED}Error: prometheus binary not found in PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Prometheus binaries installed successfully${NC}"

# Step 3: Copy prometheus.yml configuration file
echo -e "\n${YELLOW}Step 3: Installing Prometheus configuration...${NC}"
if [ -f "$SCRIPT_DIR/prometheus.yml" ]; then
    cp "$SCRIPT_DIR/prometheus.yml" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    echo -e "${GREEN}Configuration file installed to $CONFIG_FILE${NC}"
    
    # Update target to localhost if needed
    sed -i 's/YOUR_INSTANCE_IP:9705/localhost:9705/g' "$CONFIG_FILE"
else
    echo -e "${RED}Error: prometheus.yml not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Validate configuration
echo "Validating Prometheus configuration..."
if promtool check config "$CONFIG_FILE"; then
    echo -e "${GREEN}Configuration file is valid${NC}"
else
    echo -e "${YELLOW}Warning: Configuration validation had issues${NC}"
fi

# Step 4: Create systemd service
echo -e "\n${YELLOW}Step 4: Creating systemd service...${NC}"
cat > /etc/systemd/system/prometheus-agent.service <<EOF
[Unit]
Description=Prometheus Agent
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
Restart=always
RestartSec=5
ExecStart=/usr/local/bin/prometheus \\
    --config.file=$CONFIG_FILE \\
    --enable-feature=agent \\
    --storage.agent.path=$DATA_DIR/agent \\
    --web.listen-address=127.0.0.1:9090 \\
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
EOF

# Create prometheus user if it doesn't exist
if ! id "prometheus" &>/dev/null; then
    echo "Creating prometheus user..."
    useradd --no-create-home --shell /bin/false prometheus
fi

# Set ownership
chown -R prometheus:prometheus "$PROMETHEUS_DIR"
chown -R prometheus:prometheus "$DATA_DIR"
chown -R prometheus:prometheus "$DATA_DIR/agent"

# Step 5: Enable and start service
echo -e "\n${YELLOW}Step 5: Starting Prometheus Agent service...${NC}"
systemctl daemon-reload
systemctl enable prometheus-agent
systemctl start prometheus-agent

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet prometheus-agent; then
    echo -e "${GREEN}Prometheus Agent service started successfully${NC}"
else
    echo -e "${RED}Error: Prometheus Agent service failed to start${NC}"
    echo "Check logs with: sudo journalctl -u prometheus-agent -f"
    exit 1
fi

# Cleanup
echo -e "\n${YELLOW}Cleaning up temporary files...${NC}"
rm -rf "$PROMETHEUS_EXTRACTED_DIR"
# Keep tarball for future reference, but can remove it:
# rm -f "$PROMETHEUS_TARBALL"

# Summary
echo -e "\n${GREEN}=========================================="
echo "Prometheus Agent Installation Complete!"
echo "==========================================${NC}"
echo ""
echo "Service Status: sudo systemctl status prometheus-agent"
echo "View Logs: sudo journalctl -u prometheus-agent -f"
echo "Restart Service: sudo systemctl restart prometheus-agent"
echo "Configuration: $CONFIG_FILE"
echo "Data Directory: $DATA_DIR"
echo ""
echo -e "${YELLOW}Important: Update $CONFIG_FILE with your Groundcover credentials${NC}"
echo ""

