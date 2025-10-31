#!/bin/bash
set -e

# Update system
yum update -y

# Install required packages
yum install -y git wget unzip tar

# Ensure EC2 Instance Connect is available (comes pre-installed on AL2023, but verify)
# Amazon Linux 2023 includes ec2-instance-connect by default
if ! command -v /usr/bin/aws-ec2-instance-connect-cli >/dev/null 2>&1; then
    echo "EC2 Instance Connect CLI not found - installing..."
    # Note: AL2023 should have this pre-installed
    # If missing, it would be in the ec2-instance-connect package
fi

# Install .NET 8.0 Runtime and SDK
# Add Microsoft package repository
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/microsoft-prod.repo << 'EOF'
[microsoft-prod]
name=Microsoft Production Repository
baseurl=https://packages.microsoft.com/rhel/8/prod/
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# Install .NET 8.0 SDK (needed to build the application)
yum install -y dotnet-sdk-8.0

# Create application directory
mkdir -p /opt/prtg-exporter
cd /tmp

# Create a deployment script that will be run manually or via terraform
cat > /opt/prtg-exporter/deploy.sh << 'DEPLOY_EOF'
#!/bin/bash
set -e

SOURCE_DIR=$${1:-/tmp/prtg-exporter-source}

if [ ! -d "$$SOURCE_DIR" ] || [ ! -f "$$SOURCE_DIR/src/PrtgExporter.ConsoleApp/PrtgExporter.ConsoleApp.csproj" ]; then
    echo "Error: Source directory not found or invalid: $$SOURCE_DIR"
    echo "Usage: $$0 <source_directory>"
    exit 1
fi

echo "Building PRTG Exporter application from $$SOURCE_DIR..."
cd "$$SOURCE_DIR"
dotnet publish src/PrtgExporter.ConsoleApp/PrtgExporter.ConsoleApp.csproj -c Release -o /opt/prtg-exporter

echo "Build completed successfully"
DEPLOY_EOF
chmod +x /opt/prtg-exporter/deploy.sh

# Create configuration file (will be populated with actual values)
cat > /opt/prtg-exporter/prtgexporter.json.template << 'CONFIG_EOF'
{
	"PRTG": {
		"Server": "PRTG_SERVER_PLACEHOLDER",
		"Username": "PRTG_USERNAME_PLACEHOLDER",
		"Password": "PRTG_PASSHASH_PLACEHOLDER"
	},
	"Exporter": {
		"Port": "EXPORTER_PORT_PLACEHOLDER",
		"RefreshInterval": 120
	}
}
CONFIG_EOF

# Write the actual configuration
# Note: Using "Password" to match the PrtgOptions class property name
cat > /opt/prtg-exporter/prtgexporter.json << EOF
{
	"PRTG": {
		"Server": "${prtg_server}",
		"Username": "${prtg_username}",
		"Password": "${prtg_passhash}"
	},
	"Exporter": {
		"Port": "${exporter_port}",
		"RefreshInterval": 120
	}
}
EOF

echo "Configuration file created at /opt/prtg-exporter/prtgexporter.json"
echo "To complete deployment:"
echo "1. Copy prtg_exporter source to /tmp/prtg-exporter-source on this instance"
echo "2. Run: /opt/prtg-exporter/deploy.sh"
echo "3. Run: sudo systemctl start prtg-exporter"

# Create systemd service file
cat > /etc/systemd/system/prtg-exporter.service << 'SERVICE_EOF'
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
Environment="DOTNET_ROOT=/usr/share/dotnet"

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Reload systemd and enable service (but don't start until build is complete)
systemctl daemon-reload
systemctl enable prtg-exporter

# Log completion
echo "PRTG Exporter setup completed at $$(date)" >> /var/log/prtg-exporter-setup.log
