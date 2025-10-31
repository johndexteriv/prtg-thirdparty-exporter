#!/bin/bash
# Script to deploy prtg_exporter to the EC2 instance
# This script builds the application locally and uploads it
#
# Works with:
# - EC2 instances deployed via Terraform (auto-detects IP)
# - Pre-existing EC2 instances (prompts for IP if Terraform not available)
#
# IMPORTANT PREREQUISITES:
# - You must have SSH access to the EC2 instance from your current IP address
# - The security group must allow SSH (port 22) from your IP
# - SSH key must exist at ~/.ssh/prtg-exporter-key.pem (or set SSH_KEY env var)
# - Instance must be running Amazon Linux (uses ec2-user)
# 
# For pre-existing instances, ensure:
# - .NET 8.0 runtime is installed
# - Configuration file exists at /opt/prtg-exporter/prtgexporter.json (will be preserved)
# Note: Systemd service file will be created automatically if missing
#
# This script uses SSH and SCP to upload files, so SSH access is required.
# Test SSH access first: ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@<INSTANCE_IP>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}PRTG Exporter Deployment Script${NC}"
echo "========================================"

# Get instance IP from Terraform output (if available), otherwise prompt for it
EXPORTER_IP="${EXPORTER_IP:-}"
if [ -z "$EXPORTER_IP" ]; then
    # Try to get from Terraform output
    EXPORTER_IP=$(cd "$(dirname "$0")/../terraform" && terraform output -raw exporter_ipv4_address 2>/dev/null || echo "")
fi

# Prompt for IP if not found from Terraform or environment variable
if [ -z "$EXPORTER_IP" ]; then
    echo -e "${YELLOW}Exporter instance IP not found in Terraform output${NC}"
    echo "This script can work with pre-existing EC2 instances."
    read -p "Enter the EC2 instance IP address: " EXPORTER_IP
    if [ -z "$EXPORTER_IP" ]; then
        echo -e "${RED}Error: Instance IP is required${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Exporter Instance IP: ${EXPORTER_IP}${NC}"

# Check for SSH key (try prtg-exporter-key.pem first, then fallback)
SSH_KEY="${SSH_KEY:-$HOME/.ssh/prtg-exporter-key.pem}"
if [ ! -f "$SSH_KEY" ]; then
    # Try alternative locations
    if [ -f "$HOME/.ssh/prtg-exporter-key" ]; then
        SSH_KEY="$HOME/.ssh/prtg-exporter-key"
    elif [ -f "$HOME/.ssh/id_rsa" ]; then
        SSH_KEY="$HOME/.ssh/id_rsa"
    else
        echo -e "${YELLOW}Warning: SSH key not found at $SSH_KEY${NC}"
        echo "Please set SSH_KEY environment variable or ensure ~/.ssh/prtg-exporter-key.pem exists"
        read -p "Enter path to SSH key (or press Enter to use default): " SSH_KEY_INPUT
        if [ -n "$SSH_KEY_INPUT" ]; then
            SSH_KEY="$SSH_KEY_INPUT"
        fi
        if [ ! -f "$SSH_KEY" ]; then
            echo -e "${RED}SSH key required for deployment${NC}"
            exit 1
        fi
    fi
fi

echo -e "${YELLOW}Using SSH key: ${SSH_KEY}${NC}"

# Build the application locally
echo -e "\n${GREEN}Step 1: Building application locally...${NC}"
cd "$(dirname "$0")/../../prtg_exporter"
dotnet publish src/PrtgExporter.ConsoleApp/PrtgExplorer.ConsoleApp.csproj -c Release -o /tmp/prtg-exporter-build

if [ ! -f "/tmp/prtg-exporter-build/PrtgExplorer.ConsoleApp.dll" ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Build successful!${NC}"

# Create deployment package
echo -e "\n${GREEN}Step 2: Creating deployment package...${NC}"
DEPLOY_DIR="/tmp/prtg-exporter-deploy-$$"
mkdir -p "$DEPLOY_DIR"
cp -r /tmp/prtg-exporter-build/* "$DEPLOY_DIR/"

# Copy configuration file (will be overwritten with actual values from Terraform)
# Configuration is already on the instance, but we'll update it if needed

# Upload to instance (temporary directory first)
echo -e "\n${GREEN}Step 3: Uploading application to EC2 instance...${NC}"
REMOTE_TMP_DIR="/tmp/prtg-exporter-deploy-$$"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@$EXPORTER_IP "mkdir -p $REMOTE_TMP_DIR" || {
    echo -e "${RED}Failed to create remote temp directory${NC}"
    exit 1
}

scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -r "$DEPLOY_DIR"/* ec2-user@$EXPORTER_IP:$REMOTE_TMP_DIR/ || {
    echo -e "${RED}Upload failed!${NC}"
    echo "Make sure:"
    echo "  1. The instance is running"
    echo "  2. You have SSH access configured"
    echo "  3. Security group allows SSH from your IP"
    exit 1
}

echo -e "${GREEN}Upload successful!${NC}"

# Move files to /opt/prtg-exporter/ using sudo
# Note: We preserve the existing prtgexporter.json if it exists (created by Terraform or manually configured)
echo -e "\n${GREEN}Step 4: Installing application to /opt/prtg-exporter/...${NC}"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@$EXPORTER_IP "sudo mkdir -p /opt/prtg-exporter && sudo cp /opt/prtg-exporter/prtgexporter.json /opt/prtg-exporter/prtgexporter.json.backup 2>/dev/null || true && sudo cp -r $REMOTE_TMP_DIR/* /opt/prtg-exporter/ && sudo mv /opt/prtg-exporter/prtgexporter.json.backup /opt/prtg-exporter/prtgexporter.json 2>/dev/null || true && sudo chown -R root:root /opt/prtg-exporter && sudo chmod +x /opt/prtg-exporter/PrtgExplorer.ConsoleApp && rm -rf $REMOTE_TMP_DIR" || {
    echo -e "${RED}Failed to install application${NC}"
    exit 1
}

# Create systemd service file if it doesn't exist
echo -e "\n${GREEN}Step 5: Ensuring systemd service is configured...${NC}"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@$EXPORTER_IP "sudo tee /etc/systemd/system/prtg-exporter.service > /dev/null << 'EOF'
[Unit]
Description=PRTG Exporter Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/prtg-exporter
ExecStart=/usr/bin/dotnet /opt/prtg-exporter/PrtgExplorer.ConsoleApp.dll
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal
Environment=\"DOTNET_ROOT=/usr/share/dotnet\"

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable prtg-exporter" || {
    echo -e "${YELLOW}Warning: Could not create/update systemd service${NC}"
}

# Restart the service
echo -e "\n${GREEN}Step 6: Restarting PRTG Exporter service...${NC}"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@$EXPORTER_IP "sudo systemctl restart prtg-exporter && sudo systemctl status prtg-exporter" || {
    echo -e "${YELLOW}Warning: Service restart failed. Check if configuration file exists at /opt/prtg-exporter/prtgexporter.json${NC}"
}

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo ""
echo "Exporter should now be running. Check status with:"
echo "  ssh ec2-user@$EXPORTER_IP 'sudo systemctl status prtg-exporter'"
echo ""
echo "View logs with:"
echo "  ssh ec2-user@$EXPORTER_IP 'sudo journalctl -u prtg-exporter -f'"
echo ""
echo "Metrics endpoint:"
# Try to get port from Terraform, otherwise default to 9705
EXPORTER_PORT="${EXPORTER_PORT:-}"
if [ -z "$EXPORTER_PORT" ]; then
    EXPORTER_PORT=$(cd "$(dirname "$0")/../terraform" && terraform output -raw exporter_port 2>/dev/null || echo "9705")
fi
echo "  http://$EXPORTER_IP:$EXPORTER_PORT/metrics"

# Cleanup
rm -rf "$DEPLOY_DIR"
rm -rf /tmp/prtg-exporter-build

echo -e "${GREEN}Deployment package cleaned up${NC}"
