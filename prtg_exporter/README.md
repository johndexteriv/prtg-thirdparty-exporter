# PRTG Exporter

A .NET application that exposes [PRTG Network Monitor](https://www.paessler.com/prtg) metrics in Prometheus format.

This exporter is part of the PRTG Test project, which integrates PRTG Network Monitor with Prometheus for enhanced observability and metrics collection, with metrics forwarding to Groundcover's platform.

## Overview

The PRTG exporter:
- Fetches sensor and channel data from PRTG Network Monitor via HTTP API
- Exposes metrics in Prometheus format at `/metrics` endpoint
- Runs on port `9705` by default
- Integrates with Prometheus agent running on the same host

## Architecture

```
PRTG Server → PRTG Exporter (localhost:9705) → Prometheus Agent → Groundcover Platform
```

The exporter uses:
- **Direct HTTP API calls** to PRTG REST API (no external dependencies)
- **[prometheus-net](https://github.com/prometheus-net/prometheus-net)** to export metrics in Prometheus format
- **.NET 8.0** runtime

## Build

Build the project with .NET:

```bash
cd prtg_exporter
dotnet build
```

Or build in Release mode:

```bash
dotnet build -c Release
```

## Configuration

### Automatic Configuration (Production/Deployment)

When deployed via Terraform, the configuration file is **automatically created** from your `terraform.tfvars` values. The configuration file is created at `/opt/prtg-exporter/prtgexporter.json` on the EC2 instance.

**No manual configuration needed** - just ensure your `terraform.tfvars` has the correct values:
```hcl
prtg_server        = "https://your-prtg-server.com"
prtg_username      = "your-username"
prtg_passhash      = "your-passhash"
exporter_port      = 9705
```

### Local Development Configuration

For local development, create a configuration file (`prtgexporter.json`) in the application directory:

```json
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
```

**Configuration Details:**
- `Server`: PRTG server URL (use HTTPS)
- `Username`: PRTG API username
- `Password`: PRTG API passhash (found in PRTG API Token settings)
- `Port`: Port where metrics endpoint will be exposed (default: 9705)
- `RefreshInterval`: Seconds between metric refreshes (default: 120)

**Important:** The source code `prtgexporter.json` file is a template for local development only. It is **not used** in deployed instances - Terraform creates the actual config file automatically.

## Metrics Exposed

The exporter exposes the following Prometheus metrics:

- **`prtg_channel_value`** - Individual channel values from PRTG sensors
  - Labels: `sensor_id`, `device`, `sensor`, `channel`, `unit`, `probe`, `group`
  
- **`prtg_sensor_lastvalue`** - Primary channel value for each sensor
  - Labels: `sensor_id`, `device`, `sensor`, `probe`, `group`

## Running Locally

1. **Configure credentials (for local development only):**
   ```bash
   cd src/PrtgExporter.ConsoleApp
   # Edit prtgexporter.json with your PRTG credentials for local testing
   ```
   
   **Note:** When deployed via Terraform, the configuration is automatically created from `terraform.tfvars`. This file is only used for local development.

2. **Run the application:**
   ```bash
   dotnet run
   ```

3. **Verify metrics:**
   ```bash
   curl http://localhost:9705/metrics
   ```

## Deployment

This exporter is typically deployed on an EC2 instance alongside a Prometheus agent:

1. **Deploy infrastructure** (see `infrastructure/README.md`)
2. **Deploy exporter application** (see `infrastructure/scripts/deploy_exporter.sh`)
3. **Deploy Prometheus agent** (see `prometheus_agent/README.md`)

## Integration with Prometheus Agent

The PRTG exporter is designed to work with the Prometheus agent deployed on the same host:

- Exporter runs on `localhost:9705`
- Prometheus agent scrapes from `localhost:9705`
- Metrics are forwarded to Groundcover via remote write

See the main project README for complete deployment instructions.

## Network Connectivity Requirements

The PRTG exporter node requires the following network connectivity to function:

### Outbound Connections

**PRTG API Server:**
- **HTTPS (port 443)** - Primary method for connecting to PRTG REST API
- **HTTP (port 80)** - Fallback if PRTG server uses HTTP (not recommended for production)
- The exporter makes periodic API calls to `/api/table.json` endpoints
- Frequency: Every `RefreshInterval` seconds (default: 120 seconds)

**Groundcover Platform** (via Prometheus Agent on same host):
- **HTTPS (port 443)** - Prometheus agent forwards metrics via remote write
- Endpoint: Configured in `prometheus_agent/prometheus.yml` as `https://your-groundcover-instance.com/api/v1/write`
- This is handled by the Prometheus agent, not the exporter directly

### Inbound Connections

**Metrics Endpoint (port 9705):**
- Exposed on `localhost` only - Prometheus agent on the same host scrapes this endpoint
- No external network access required for the metrics endpoint
- The security group may allow external access, but it's not needed for normal operation

**SSH (port 22):**
- Required for deployment and management
- Configured via security group rules in Terraform

### Security Group Configuration

When deployed via Terraform, the security group is automatically configured with:
- ✅ Outbound HTTPS (443) - For PRTG API access
- ✅ Outbound HTTP (80) - Fallback for PRTG API access
- ✅ Outbound HTTPS (443) - For general connectivity (includes Groundcover remote write)
- ✅ Inbound SSH (22) - For management (restricted to allowed CIDR)

### Troubleshooting Network Issues

If the exporter is not collecting data:

```bash
# Test PRTG API connectivity from the instance
ssh ec2-user@<INSTANCE_IP> 'curl -I https://your-prtg-server.com/api/table.json'

# Check if DNS resolution works
ssh ec2-user@<INSTANCE_IP> 'nslookup your-prtg-server.com'

# Verify exporter can reach PRTG
ssh ec2-user@<INSTANCE_IP> 'curl -v https://your-prtg-server.com/api/table.json?content=sensors&username=test'
```

If metrics are not appearing in Groundcover:

```bash
# Test Groundcover connectivity from the instance  
ssh ec2-user@<INSTANCE_IP> 'curl -I https://your-groundcover-instance.com/api/v1/write'

# Check Prometheus agent logs for remote write errors
ssh ec2-user@<INSTANCE_IP> 'sudo journalctl -u prometheus-agent -f | grep -i "remote\|write\|error"'
```

## Development

### Project Structure

```
prtg_exporter/
├── src/
│   └── PrtgExporter.ConsoleApp/
│       ├── PrtgExporter.cs      # Core exporter logic
│       ├── Program.cs            # Application entry point
│       ├── Options/              # Configuration classes
│       └── prtgexporter.json     # Configuration file
└── README.md
```

### Testing

Test locally before deploying:

```bash
# Build and run
dotnet run

# In another terminal, check metrics
curl http://localhost:9705/metrics | grep prtg
```

## Troubleshooting

- **Check logs:** `ssh ec2-user@<INSTANCE_IP> 'sudo journalctl -u prtg-exporter -f'`
- **Verify configuration:** Check `/opt/prtg-exporter/prtgexporter.json` on the instance (created by Terraform)
- **Test PRTG connectivity:** Verify you can reach PRTG API from the host
- **Check metrics endpoint:** `curl http://<INSTANCE_IP>:9705/metrics`
- **Update credentials:** Update `terraform.tfvars` and re-run `terraform apply`, OR manually edit `/opt/prtg-exporter/prtgexporter.json` on the instance

## License

This project is part of the PRTG Test project. See the main project README for license information.
