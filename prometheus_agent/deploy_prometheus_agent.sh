#!/bin/bash

# Deploy Prometheus Agent to EC2 instance
# This script uploads the prometheus_agent directory and runs the installation script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${GREEN}Prometheus Agent Deployment Script${NC}"
echo "=========================================="

# Get exporter instance IP from Terraform output (if available)
EXPORTER_IP="${EXPORTER_IP:-}"
if [ -z "$EXPORTER_IP" ] && [ -d "$PROJECT_ROOT/infrastructure/terraform" ]; then
    cd "$PROJECT_ROOT/infrastructure/terraform"
    EXPORTER_IP=$(terraform output -raw exporter_ipv4_address 2>/dev/null || echo "")
    cd - > /dev/null
fi

# Prompt for IP if not found
if [ -z "$EXPORTER_IP" ]; then
    echo -e "${YELLOW}Exporter instance IP not found in Terraform output${NC}"
    read -p "Enter the EC2 instance IP address: " EXPORTER_IP
    if [ -z "$EXPORTER_IP" ]; then
        echo -e "${RED}Error: Instance IP is required${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Target instance: $EXPORTER_IP${NC}"

# Check for SSH key
SSH_KEY="${SSH_KEY:-$HOME/.ssh/prtg-exporter-key.pem}"
if [ ! -f "$SSH_KEY" ]; then
    if [ -f "$HOME/.ssh/prtg-exporter-key" ]; then
        SSH_KEY="$HOME/.ssh/prtg-exporter-key"
    else
        echo -e "${YELLOW}Warning: SSH key not found at $SSH_KEY${NC}"
        read -p "Enter path to SSH key (or press Enter to use default): " SSH_KEY_INPUT
        if [ -n "$SSH_KEY_INPUT" ]; then
            SSH_KEY="$SSH_KEY_INPUT"
        else
            SSH_KEY="$HOME/.ssh/id_rsa"
        fi
    fi
fi

if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}Error: SSH key not found at $SSH_KEY${NC}"
    exit 1
fi

echo -e "${YELLOW}Using SSH key: $SSH_KEY${NC}"

# Check if prometheus.yml exists
if [ ! -f "$SCRIPT_DIR/prometheus.yml" ]; then
    echo -e "${RED}Error: prometheus.yml not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Check if installation script exists
if [ ! -f "$SCRIPT_DIR/install_prometheus_agent.sh" ]; then
    echo -e "${RED}Error: install_prometheus_agent.sh not found in $SCRIPT_DIR${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Important: Make sure prometheus.yml is configured with your Groundcover credentials${NC}"
read -p "Continue with deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Deployment cancelled"
    exit 0
fi

# Create temporary directory on remote host
echo -e "\n${YELLOW}Uploading Prometheus Agent files...${NC}"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@"$EXPORTER_IP" \
    "mkdir -p /tmp/prometheus_agent"

# Upload files
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/prometheus.yml" \
    "$SCRIPT_DIR/install_prometheus_agent.sh" \
    ec2-user@"$EXPORTER_IP":/tmp/prometheus_agent/

# Make installation script executable
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@"$EXPORTER_IP" \
    "chmod +x /tmp/prometheus_agent/install_prometheus_agent.sh"

# Run installation script
echo -e "\n${YELLOW}Installing Prometheus Agent...${NC}"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@"$EXPORTER_IP" \
    "sudo /tmp/prometheus_agent/install_prometheus_agent.sh"

# Check service status
echo -e "\n${YELLOW}Checking Prometheus Agent service status...${NC}"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@"$EXPORTER_IP" \
    "sudo systemctl status prometheus-agent --no-pager || true"

echo -e "\n${GREEN}=========================================="
echo "Prometheus Agent Deployment Complete!"
echo "==========================================${NC}"
echo ""
echo "Service Status: ssh ec2-user@$EXPORTER_IP 'sudo systemctl status prometheus-agent'"
echo "View Logs: ssh ec2-user@$EXPORTER_IP 'sudo journalctl -u prometheus-agent -f'"
echo "Configuration: /etc/prometheus/prometheus.yml"
echo ""
echo -e "${YELLOW}Remember to update /etc/prometheus/prometheus.yml with your Groundcover credentials if not already done${NC}"
echo ""

