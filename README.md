# PRTG Test Project

A comprehensive monitoring solution that integrates PRTG Network Monitor with Prometheus for enhanced observability and metrics collection, with metrics forwarding to Groundcover's platform.

## 🏗️ Architecture Overview

This project deploys monitoring infrastructure and applications:

1. **PRTG Exporter Instance** - Runs a custom .NET application that exposes PRTG metrics in Prometheus format
2. **SNMP Monitoring Instance** - Provides SNMP monitoring capabilities for PRTG to collect system metrics
3. **Prometheus Agent** - Runs on the exporter instance, scrapes metrics and forwards to Groundcover

```
PRTG Server → PRTG Exporter (localhost:9705) → Prometheus Agent → Groundcover Platform
```

## 📁 Project Structure

```
prtg_test/
├── infrastructure/           # AWS infrastructure as code
│   ├── terraform/           # Terraform configuration files
│   ├── scripts/             # Deployment scripts
│   └── config/              # User data scripts for EC2 initialization
├── prtg_exporter/           # .NET application source code
│   └── src/                 # C# source code
└── prometheus_agent/        # Prometheus agent installation
    ├── prometheus.yml       # Prometheus configuration
    ├── install_prometheus_agent.sh  # Installation script
    └── deploy_prometheus_agent.sh   # Deployment script
```

## 🚀 Deployment Methods

### Method 1: Deploy from Scratch (Full Deployment)

Deploy everything including AWS infrastructure, PRTG exporter, and Prometheus agent.

#### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform installed (>= 1.0)
- .NET 8.0 SDK installed
- SSH key pair for EC2 access (`~/.ssh/prtg-exporter-key.pem`)
- PRTG server credentials
- Groundcover remote write URL and API key

#### Step 1: Configure Terraform Variables

Edit `infrastructure/terraform/terraform.tfvars`:

```hcl
# EC2 Instance Configuration
instance_type      = "t3.medium"
allowed_ssh_cidr   = "0.0.0.0/0"  # Or restrict to your IP/32
allowed_snmp_cidr  = "YOUR_PRTG_SERVER_IP/32"

# SNMP Monitoring Configuration
snmp_community     = "your-secure-community-string"

# PRTG Exporter Configuration (REQUIRED)
prtg_server        = "https://your-prtg-server.com"  # Required - no default
prtg_username      = "your-username"
prtg_passhash      = "your-passhash"
exporter_port      = 9705
```

**Important:** The `prtg_server` variable is required and must be explicitly set. No default value is provided for security reasons.

#### Step 2: Deploy Infrastructure

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

This creates:
- Two EC2 instances (Instance running PRTG Exporter and Prometheus Agent and an Instance for testing PRTG SNMP Monitoring)
- Security groups
- IAM roles
- Configuration file at `/opt/prtg-exporter/prtgexporter.json` (auto-generated)

**Save the exporter IP** shown in Terraform output for later steps.

#### Step 3: Deploy PRTG Exporter Application

```bash
cd infrastructure/scripts
./deploy_exporter.sh
```

**Important:** This script requires SSH access from your IP address. If it fails:
1. Verify SSH works: `ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@<EXPORTER_IP>`
2. Check security group allows SSH from your IP
3. Update `allowed_ssh_cidr` in `terraform.tfvars` if needed

The script will:
- Build the application locally
- Upload files to the instance
- Preserve the Terraform-generated configuration
- Install and start the service

#### Step 4: Configure Prometheus Agent

Edit `prometheus_agent/prometheus.yml` with your Groundcover credentials:

```yaml
remote_write:
  - url: "https://your-groundcover-instance.com/api/v1/write"
    headers:
      apikey: "your-groundcover-api-key"
```

#### Step 5: Deploy Prometheus Agent

```bash
cd prometheus_agent
./deploy_prometheus_agent.sh
```

This will:
- Upload Prometheus agent files
- Install Prometheus in agent mode
- Configure scraping from `localhost:9705`
- Set up systemd service

#### Step 6: Verify Deployment

```bash
# Get exporter IP
EXPORTER_IP=$(cd infrastructure/terraform && terraform output -raw exporter_ipv4_address)

# Test PRTG exporter metrics
curl http://$EXPORTER_IP:9705/metrics | grep "^prtg_" | head -5

# Check Prometheus agent status
ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@$EXPORTER_IP \
    'sudo systemctl status prometheus-agent'
```

---

### Method 2: Deploy to Pre-Existing EC2 Instances

Deploy PRTG exporter and Prometheus agent to existing EC2 instances.

#### Prerequisites

- Pre-existing EC2 instance(s) running Amazon Linux
- .NET 8.0 runtime installed on the exporter instance (or install it)
- SSH access to the instance(s)
- SSH key (`~/.ssh/prtg-exporter-key.pem` or set `SSH_KEY` env var)
- PRTG server credentials
- Groundcover remote write URL and API key

#### Step 1: Prepare the Instance

**For PRTG Exporter:**

1. Install .NET 8.0 runtime (if not already installed):
   ```bash
   sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
   sudo sh -c 'echo -e "[packages-microsoft-com-prod]\nname=packages-microsoft-com-prod\nbaseurl=https://packages.microsoft.com/rhel/8/prod/\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/microsoft-prod.repo'
   sudo yum install -y dotnet-runtime-8.0
   ```

2. Create configuration file (required):
   ```bash
   sudo mkdir -p /opt/prtg-exporter
   sudo tee /opt/prtg-exporter/prtgexporter.json > /dev/null <<EOF
   {
       "PRTG": {
           "Server": "https://your-prtg-server.com",
           "Username": "your-username",
           "Password": "your-passhash"
       },
       "Exporter": {
           "Port": "9705",
           "RefreshInterval": 120
       }
   }
   EOF
   ```
   
   **Note:** The deployment script will create the systemd service file automatically. Only the configuration file needs to be created manually.

#### Step 2: Deploy PRTG Exporter

```bash
# Set instance IP as environment variable or enter when prompted
export EXPORTER_IP="your-instance-ip"

# Deploy
cd infrastructure/scripts
./deploy_exporter.sh
```

The script will prompt for the IP if not set via Terraform or environment variable.

#### Step 3: Configure Prometheus Agent

Edit `prometheus_agent/prometheus.yml` with your Groundcover credentials (same as Method 1).

#### Step 4: Deploy Prometheus Agent

```bash
# Set instance IP if needed
export EXPORTER_IP="your-instance-ip"

cd prometheus_agent
./deploy_prometheus_agent.sh
```

The script will prompt for the IP if not provided.

#### Step 5: Verify Deployment

```bash
# Test metrics
curl http://$EXPORTER_IP:9705/metrics | grep "^prtg_"

# Check services
ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@$EXPORTER_IP \
    'sudo systemctl status prtg-exporter prometheus-agent'
```

---

## 🌐 Networking Requirements

The PRTG exporter node requires specific network connectivity to function properly:

### Outbound Connectivity

**PRTG Exporter → PRTG API:**
- **HTTPS (port 443)** - Required for connecting to PRTG server API
- **HTTP (port 80)** - Optional fallback if PRTG server uses HTTP
- The exporter makes periodic API calls to fetch sensor and channel data from PRTG

**Prometheus Agent → Groundcover Platform:**
- **HTTPS (port 443)** - Required for remote write to Groundcover's API endpoint
- The Prometheus agent forwards scraped metrics to Groundcover via remote write
- Configure the endpoint in `prometheus_agent/prometheus.yml` as `https://your-groundcover-instance.com/api/v1/write`

### Inbound Connectivity

**SSH Access (port 22):**
- Required for deployment and management
- Configured via `allowed_ssh_cidr` in `terraform.tfvars`

**Metrics Endpoint (port 9705):**
- Exposed on localhost only (scraped by Prometheus agent on the same host)
- No external network access required for metrics endpoint
- Security group allows external access, but Prometheus agent connects locally

### Security Group Configuration

The Terraform configuration automatically sets up:
- ✅ Outbound HTTPS (443) to PRTG API
- ✅ Outbound HTTP (80) to PRTG API  
- ✅ Outbound HTTPS (443) for general connectivity (includes Groundcover)
- ✅ Inbound SSH (22) from allowed CIDR blocks

### Testing Network Connectivity

If experiencing connectivity issues, test from the instance:

```bash
# Test PRTG API connectivity
curl -I https://your-prtg-server.com/api/table.json

# Test Groundcover endpoint connectivity  
curl -I https://your-groundcover-instance.com/api/v1/write

# Check DNS resolution
nslookup your-prtg-server.com
nslookup your-groundcover-instance.com
```

---

## 🔧 Configuration

### Terraform Variables

The `infrastructure/terraform/terraform.tfvars` file controls infrastructure deployment:

- `prtg_server` - **Required**, no default. PRTG server URL
- `prtg_username` - PRTG API username
- `prtg_passhash` - PRTG API passhash (from PRTG API Token settings)
- `allowed_ssh_cidr` - CIDR block allowed SSH access
- `allowed_snmp_cidr` - CIDR block allowed SNMP access
- `snmp_community` - SNMP community string

### Prometheus Agent Configuration

The `prometheus_agent/prometheus.yml` file controls metrics collection:

- `scrape_configs` - Configured to scrape `localhost:9705` (PRTG exporter)
- `remote_write` - Must be updated with your Groundcover URL and API key

### PRTG Exporter Configuration

- **Terraform-deployed instances**: Configuration auto-generated at `/opt/prtg-exporter/prtgexporter.json`
- **Pre-existing instances**: Manually create `/opt/prtg-exporter/prtgexporter.json` (see Method 2, Step 1)

---

## 📊 Metrics Available

The PRTG exporter exposes:

- **`prtg_channel_value`** - Individual channel values with labels: `sensor_id`, `device`, `sensor`, `channel`, `unit`, `probe`, `group`
- **`prtg_sensor_lastvalue`** - Primary channel value for each sensor with labels: `sensor_id`, `device`, `sensor`, `probe`, `group`

---

## 🛠️ Management

### Get Instance Information

```bash
cd infrastructure/terraform
terraform output
```

### Check Service Status

```bash
# PRTG Exporter
ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@<EXPORTER_IP> \
    'sudo systemctl status prtg-exporter'

# Prometheus Agent
ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@<EXPORTER_IP> \
    'sudo systemctl status prometheus-agent'
```

### View Logs

```bash
# PRTG Exporter logs
ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@<EXPORTER_IP> \
    'sudo journalctl -u prtg-exporter -f'

# Prometheus Agent logs
ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@<EXPORTER_IP> \
    'sudo journalctl -u prometheus-agent -f'
```

### Update Application

```bash
cd infrastructure/scripts
./deploy_exporter.sh  # Re-deploys PRTG exporter
```

### Destroy Infrastructure

```bash
cd infrastructure/terraform
terraform destroy
```

**Warning:** This permanently deletes all instances and resources.

---

## 🔍 Troubleshooting

### SSH Access Fails

- Verify security group allows SSH from your IP
- Check SSH key exists: `ls ~/.ssh/prtg-exporter-key.pem`
- Test manually: `ssh -i ~/.ssh/prtg-exporter-key.pem ec2-user@<IP>`
- Update `allowed_ssh_cidr` in `terraform.tfvars` if needed

### Exporter Not Collecting Metrics

- Check logs: `sudo journalctl -u prtg-exporter -f`
- Verify PRTG credentials in `/opt/prtg-exporter/prtgexporter.json`
- Ensure JSON uses `"Password"` (not `"passhash"`)
- Test PRTG API connectivity from the instance

### Prometheus Agent Not Scraping

- Check target health: `curl http://localhost:9090/api/v1/targets` (on instance)
- Verify exporter is running: `curl http://localhost:9705/metrics`
- Check agent logs: `sudo journalctl -u prometheus-agent -f`

### No Metrics in Groundcover

- Verify `prometheus.yml` has correct Groundcover URL and API key
- Check agent logs for remote write errors
- Verify network connectivity from instance to Groundcover endpoint

---

## 📝 Additional Documentation

- **Infrastructure details**: See `infrastructure/README.md`
- **PRTG Exporter details**: See `prtg_exporter/README.md`
- **Prometheus Agent details**: See `prometheus_agent/README.md`

---

## 🔒 Security Considerations

- Change default SNMP community string in production
- Restrict SSH access to specific IP ranges (`allowed_ssh_cidr`)
- Use IAM roles with minimal required permissions
- Regularly update instance AMIs and packages
- Keep `terraform.tfvars` and `prometheus.yml` out of version control

---

**Note:** This project is designed for testing and development purposes. For production use, ensure proper security hardening and monitoring practices are implemented.
