#!/bin/bash
set -e

# Update system
yum update -y

# Install SNMP service
yum install -y net-snmp net-snmp-utils

# Start SNMP service
systemctl enable snmpd
systemctl start snmpd

# Configure SNMP (basic configuration with public community)
# Note: In production, you should use a more secure community string
cat > /etc/snmp/snmpd.conf << 'EOF'
# Listen on all interfaces (0.0.0.0 means all IPv4 interfaces)
agentAddress udp:0.0.0.0:161

# Create a view for system-wide access
view   systemview  included   .1

# Default community (public) - CHANGE THIS IN PRODUCTION!
# Allow read-only access to entire MIB tree
rocommunity public default -V systemview

# System contact and location
syscontact root@localhost
syslocation Unknown

# Enable all standard MIBs
view   systemonly  included   .1.3.6.1.2.1.1
view   systemonly  included   .1.3.6.1.2.1.25.1
view   systemonly  included   .1.3.6.1.4.1.2021

# Enable agentX for SNMP subagents
master agentx

# Set system OIDs
sysName    Linux
sysDescr   Amazon Linux Host

# Disable authentication traps
disableAuthentication yes

# Allow SNMP v1 and v2c
rocommunity public
EOF

# Restart SNMP service to apply configuration
systemctl restart snmpd

# Verify SNMP is running
systemctl status snmpd

# Log completion
echo "SNMP configuration completed at $(date)" >> /var/log/snmp-setup.log
