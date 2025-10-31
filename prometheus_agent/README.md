# Prometheus Agent

This directory contains the Prometheus agent installation and configuration files.

## Overview

The Prometheus agent runs on the same host as the PRTG exporter and:
- Scrapes metrics from the PRTG exporter at `localhost:9705`
- Forwards metrics to Groundcover's platform via remote write
- Runs in agent mode (no local storage, minimal resource usage)

## Files

- `prometheus.yml` - Prometheus configuration file (scrape config + remote write)
- `install_prometheus_agent.sh` - Installation script for Linux

## Installation

### Prerequisites

- Linux system (Amazon Linux 2023, Ubuntu, etc.)
- Root/sudo access
- PRTG exporter must be running on `localhost:9705`

### Step 1: Update Configuration

Before installing, update `prometheus.yml` with your Groundcover credentials:

```yaml
remote_write:
  - url: "https://your-groundcover-instance.com/api/v1/write"
    headers:
      apikey: "your-groundcover-api-key"
```

### Step 2: Run Installation Script

On the host where PRTG exporter is running:

```bash
# Copy the prometheus_agent directory to the instance
scp -r prometheus_agent/ ec2-user@<INSTANCE_IP>:~/

# SSH into the instance
ssh ec2-user@<INSTANCE_IP>

# Run the installation script
cd prometheus_agent
sudo ./install_prometheus_agent.sh
```

The script will:
1. Download the latest Prometheus Linux binary
2. Extract and install binaries to `/usr/local/bin/`
3. Create necessary directories (`/etc/prometheus`, `/var/lib/prometheus`)
4. Copy `prometheus.yml` to `/etc/prometheus/prometheus.yml`
5. Create a systemd service (`prometheus-agent`)
6. Start and enable the service

## Service Management

```bash
# Check status
sudo systemctl status prometheus-agent

# View logs
sudo journalctl -u prometheus-agent -f

# Restart service
sudo systemctl restart prometheus-agent

# Stop service
sudo systemctl stop prometheus-agent

# Enable on boot
sudo systemctl enable prometheus-agent
```

## Configuration

The Prometheus agent configuration file is located at:
```
/etc/prometheus/prometheus.yml
```

After updating the configuration:
```bash
# Validate configuration
sudo promtool check config /etc/prometheus/prometheus.yml

# Reload service (if lifecycle API is enabled)
sudo systemctl reload prometheus-agent
# Or restart
sudo systemctl restart prometheus-agent
```

## Verification

1. **Check service is running:**
   ```bash
   sudo systemctl status prometheus-agent
   ```

2. **Verify metrics endpoint (if web UI is enabled):**
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

3. **Check logs for errors:**
   ```bash
   sudo journalctl -u prometheus-agent -n 50
   ```

4. **Verify remote write is working:**
   - Check Groundcover platform for incoming metrics
   - Look for successful remote write in logs

## Troubleshooting

### Service fails to start

1. Check logs: `sudo journalctl -u prometheus-agent -f`
2. Validate config: `sudo promtool check config /etc/prometheus/prometheus.yml`
3. Check permissions on config and data directories:
   ```bash
   sudo ls -la /etc/prometheus/
   sudo ls -la /var/lib/prometheus/
   ```

### No metrics being scraped

1. Verify PRTG exporter is running:
   ```bash
   curl http://localhost:9705/metrics
   ```
2. Check firewall rules (port 9705 should be accessible)
3. Verify scrape config in `prometheus.yml` uses `localhost:9705`

### Remote write failures

1. Verify Groundcover URL and API key in `prometheus.yml`
2. Check network connectivity to Groundcover endpoint
3. Review logs for specific error messages:
   ```bash
   sudo journalctl -u prometheus-agent | grep -i "remote\|write\|error"
   ```

## Manual Installation (Alternative)

If you prefer to install manually:

```bash
# Download and extract
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
tar -xzf prometheus-*.linux-amd64.tar.gz

# Install binaries
sudo mv prometheus-*/prometheus prometheus-*/promtool /usr/local/bin/

# Create directories
sudo mkdir -p /etc/prometheus /var/lib/prometheus

# Copy configuration
sudo cp prometheus.yml /etc/prometheus/prometheus.yml

# Run Prometheus agent
prometheus --config.file=/etc/prometheus/prometheus.yml --enable-feature=agent
```

## References

- [Prometheus Download](https://prometheus.io/download/)
- [Prometheus Agent Mode Blog](https://prometheus.io/blog/2021/11/16/agent/)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)

