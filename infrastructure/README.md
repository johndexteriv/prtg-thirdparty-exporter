# Infrastructure

This directory contains all the infrastructure-as-code components for the PRTG Test project, organized into logical subdirectories.

## 📁 Directory Structure

```
infrastructure/
├── terraform/           # Terraform configuration files
│   ├── main.tf         # Core infrastructure (SNMP monitoring instance)
│   ├── prtg_exporter.tf # PRTG exporter instance configuration
│   ├── variables.tf    # Variable definitions
│   ├── terraform.tfvars # Configuration values
│   └── terraform.tfstate* # State files
├── scripts/            # Deployment and management scripts
│   └── deploy_exporter.sh # Deployment script with error handling and config preservation
└── config/             # User data scripts for EC2 initialization
    ├── user_data.sh    # SNMP monitoring instance setup
    └── prtg_exporter_user_data.sh # PRTG exporter instance setup
```

## 🚀 Quick Start

### 1. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Deploy PRTG Exporter Application

**Important:** Ensure your IP address is allowed SSH access to the instance. Check `terraform.tfvars` - the `allowed_ssh_cidr` setting controls SSH access. If you're having connection issues, verify your IP is included in the security group rules.

```bash
cd ../scripts
./deploy_exporter.sh
```

This script requires SSH access from your current IP address. If SSH access fails, update the security group to allow your IP.

### 3. Deploy Prometheus Agent

The Prometheus agent runs on the same host as the PRTG exporter to scrape and forward metrics:

```bash
cd ../../prometheus_agent
./deploy_prometheus_agent.sh
```

**Note:** Make sure to update `prometheus_agent/prometheus.yml` with your Groundcover credentials before deploying.

## 📋 Prerequisites

- AWS CLI configured
- Terraform >= 1.0
- .NET 8.0 SDK
- SSH key pair (`prtg-exporter-key`)

## ⚙️ Configuration

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
# EC2 Instance Configuration
instance_type      = "t3.medium"
allowed_ssh_cidr   = "0.0.0.0/0"
allowed_snmp_cidr  = "YOUR_IP/32"

# SNMP Monitoring Configuration
snmp_community     = "your-secure-community-string"

# PRTG Exporter Configuration
prtg_server        = "http://your-prtg-server.com"
prtg_username      = "your-username"
prtg_passhash      = "your-passhash"
exporter_port      = 9705
```

## 🏗️ Infrastructure Components

### SNMP Monitoring Instance (`main.tf`)

- **Purpose:** Provides SNMP monitoring capabilities for PRTG
- **AMI:** Amazon Linux 2023
- **Services:** SNMP daemon configured with public community
- **Security Group:** Allows SNMP (UDP 161) and SSH (TCP 22)

### PRTG Exporter Instance (`prtg_exporter.tf`)

- **Purpose:** Runs the custom .NET application that exposes PRTG metrics
- **AMI:** Amazon Linux 2023
- **Services:** 
  - .NET 8.0 runtime
  - PRTG exporter service (port 9705)
  - Prometheus agent (deployed separately, scrapes from localhost:9705)
- **Security Group:** 
  - **Inbound:** SSH (22) from allowed CIDR, metrics endpoint (9705) 
  - **Outbound:** HTTPS (443) to PRTG API, HTTP (80) to PRTG API, all outbound for package installation
- **Integration:** Works with Prometheus agent on same host for metrics forwarding

#### Network Connectivity Requirements

The PRTG exporter instance requires the following network connectivity:

**Outbound Connections:**
- **PRTG API** - HTTPS (443) or HTTP (80) to reach the PRTG server API
  - The exporter makes periodic API calls to fetch sensor and channel data
  - Configured via `prtg_server` in `terraform.tfvars`
- **Groundcover Platform** - HTTPS (443) for remote write endpoint
  - Prometheus agent sends metrics to Groundcover's remote write API
  - Configured in `prometheus_agent/prometheus.yml`
- **Package Repositories** - HTTPS (443) for installing .NET runtime and packages

**Inbound Connections:**
- **SSH (22)** - For deployment and management (restricted to `allowed_ssh_cidr`)
- **Metrics Endpoint (9705)** - Exposed on localhost for Prometheus agent scraping
  - No external network access needed (Prometheus agent runs on the same host)

The security group automatically configures these rules when deployed via Terraform.

## 📜 Scripts

### `deploy_exporter.sh`

Full-featured deployment script with:
- Error handling and colored output
- SSH key detection and validation
- Application building and packaging
- Service restart and status checking

**Important Prerequisites:**
- **SSH access required**: You must be able to SSH into the instance from your IP address
- The security group must allow SSH (port 22) from your IP address
- Your IP should be configured in `terraform.tfvars` as `allowed_ssh_cidr` or use `0.0.0.0/0` for testing
- SSH key must exist at `~/.ssh/prtg-exporter-key.pem` or `~/.ssh/prtg-exporter-key`

**Usage:**
```bash
./deploy_exporter.sh
```

**Note:** This script will fail if you cannot SSH to the instance. Ensure your IP is allowed in the security group before running.

## 🔧 User Data Scripts

### `config/user_data.sh`

Configures the SNMP monitoring instance:
- Installs and configures SNMP daemon
- Sets up community string (public)
- Enables and starts SNMP service
- Configures basic SNMP settings

### `config/prtg_exporter_user_data.sh`

Configures the PRTG exporter instance:
- Installs .NET 8.0 SDK and runtime
- Creates application directory structure
- Sets up systemd service (`prtg-exporter`)
- **Creates `/opt/prtg-exporter/prtgexporter.json` automatically** from Terraform variables
- Configures PRTG connection parameters from `terraform.tfvars`

**Important Configuration Notes:**
- ✅ **Configuration is auto-generated** - No need to manually update `prtgexporter.json` before deployment
- ✅ **Deployment script preserves config** - `deploy_exporter.sh` preserves the Terraform-generated config file
- 📝 **Source code file is template only** - `prtg_exporter/src/PrtgExporter.ConsoleApp/prtgexporter.json` is for local development

**Note:** Prometheus agent is deployed separately using `prometheus_agent/deploy_prometheus_agent.sh`

## 🔍 Troubleshooting

### Common Issues

1. **Terraform Apply Fails:**
   - Check AWS credentials: `aws sts get-caller-identity`
   - Verify region and availability zones
   - Ensure required permissions are granted

2. **Deployment Script Fails:**
   - **SSH Access Required**: The deployment script uses SSH and SCP to upload files. You must have SSH access from your current IP address.
   - Verify SSH key exists: `ls ~/.ssh/prtg-exporter-key*`
   - Test SSH connection manually: `ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@<INSTANCE_IP>`
   - Check instance is running: `aws ec2 describe-instances`
   - Verify security group allows SSH from your IP: Check `allowed_ssh_cidr` in `terraform.tfvars`
   - If SSH fails, update Terraform to allow your IP and run `terraform apply`

3. **Application Won't Start:**
   - Check logs: `ssh ec2-user@<IP> 'sudo journalctl -u prtg-exporter -f'`
   - Verify PRTG credentials in configuration
   - Ensure .NET runtime is installed

4. **Prometheus Agent Not Scraping:**
   - Verify PRTG exporter is running: `curl http://localhost:9705/metrics`
   - Check Prometheus agent status: `ssh ec2-user@<IP> 'sudo systemctl status prometheus-agent'`
   - Review agent logs: `ssh ec2-user@<IP> 'sudo journalctl -u prometheus-agent -f'`
   - Verify configuration at `/etc/prometheus/prometheus.yml`

### Useful Commands

```bash
# Get instance IPs
cd terraform
terraform output

# Check service status
ssh ec2-user@<EXPORTER_IP> 'sudo systemctl status prtg-exporter'

# View application logs
ssh ec2-user@<EXPORTER_IP> 'sudo journalctl -u prtg-exporter -f'

# Test SNMP
snmpwalk -v2c -c public <SNMP_IP>

# Test metrics endpoint
curl http://<EXPORTER_IP>:9705/metrics

# Check Prometheus agent status
ssh ec2-user@<EXPORTER_IP> 'sudo systemctl status prometheus-agent'

# View Prometheus agent logs
ssh ec2-user@<EXPORTER_IP> 'sudo journalctl -u prometheus-agent -f'

# Verify agent can scrape exporter
ssh ec2-user@<EXPORTER_IP> 'curl http://localhost:9705/metrics | head -20'
```

## 🔒 Security Notes

- Change default SNMP community string in production
- Restrict SSH access to specific IP ranges
- Use IAM roles with minimal permissions
- Regularly update AMIs and packages
- Consider VPC endpoints for enhanced security

## 📊 Outputs

After successful deployment, Terraform provides:

- `instance_id` - SNMP monitoring instance ID
- `ipv4_address` - SNMP instance public IP
- `exporter_instance_id` - PRTG exporter instance ID
- `exporter_ipv4_address` - Exporter instance public IP
- `exporter_metrics_url` - Full metrics endpoint URL

## 🔄 Deployment Workflow

The complete deployment workflow is:

1. **Deploy Infrastructure** (Terraform)
   ```bash
   cd terraform
   terraform apply
   ```

2. **Deploy PRTG Exporter** (Application)
   ```bash
   cd ../scripts
   ./deploy_exporter.sh
   ```

3. **Deploy Prometheus Agent** (Metrics Collection)
   ```bash
   cd ../../prometheus_agent
   # Update prometheus.yml with Groundcover credentials first
   ./deploy_prometheus_agent.sh
   ```

4. **Verify Everything Works**
   - PRTG exporter metrics: `curl http://<EXPORTER_IP>:9705/metrics`
   - Prometheus agent status: `ssh ec2-user@<EXPORTER_IP> 'sudo systemctl status prometheus-agent'`
   - Check Groundcover platform for incoming metrics

## 🧹 Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**Warning:** This will permanently delete all instances and associated resources.

