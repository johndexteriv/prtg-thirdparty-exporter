# PRTG Exporter EC2 Instance
# This instance runs the prtg_exporter to expose PRTG metrics for Prometheus

# Security group for PRTG exporter
resource "aws_security_group" "prtg_exporter" {
  name        = "prtg-exporter"
  description = "Security group for PRTG exporter instance"
  vpc_id      = data.aws_vpc.default.id

  # Allow metrics endpoint access (for Prometheus scraping)
  ingress {
    description = "Prometheus metrics endpoint"
    from_port   = var.exporter_port
    to_port     = var.exporter_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict to Prometheus server IP if needed
  }

  # Allow SSH access (for management)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Allow outbound HTTPS (for PRTG API access)
  egress {
    description = "HTTPS to PRTG API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound HTTP (in case PRTG uses HTTP)
  egress {
    description = "HTTP to PRTG API"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound for package installation
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prtg-exporter"
  }
}

# IAM role for exporter EC2 instance
resource "aws_iam_role" "exporter_role" {
  name = "prtg-exporter-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "prtg-exporter-ec2-role"
  }
}

# Attach SSM managed policy (required for EC2 Instance Connect and Systems Manager)
resource "aws_iam_role_policy_attachment" "exporter_ssm" {
  role       = aws_iam_role.exporter_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for exporter
resource "aws_iam_instance_profile" "exporter_profile" {
  name = "prtg-exporter-ec2-profile"
  role = aws_iam_role.exporter_role.name
}

# Variables for PRTG exporter configuration
variable "prtg_server" {
  description = "PRTG server URL"
  type        = string
}

variable "prtg_username" {
  description = "PRTG API username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "prtg_passhash" {
  description = "PRTG API passhash"
  type        = string
  default     = ""
  sensitive   = true
}

variable "exporter_port" {
  description = "Port for metrics endpoint"
  type        = number
  default     = 9705
}

# Note: Application deployment happens after instance creation
# Use the deploy_exporter.sh script to build and deploy the application
# Or manually upload and run the deploy script on the instance

# EC2 instance for PRTG exporter
resource "aws_instance" "prtg_exporter" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids = [aws_security_group.prtg_exporter.id]
  iam_instance_profile   = aws_iam_instance_profile.exporter_profile.name
  key_name               = "prtg-exporter-key"
  
  user_data = templatefile("${path.module}/../config/prtg_exporter_user_data.sh", {
    prtg_server    = var.prtg_server
    prtg_username  = var.prtg_username
    prtg_passhash  = var.prtg_passhash
    exporter_port  = var.exporter_port
  })

  tags = {
    Name = "prtg-exporter"
  }
}

# Outputs for PRTG exporter
output "exporter_instance_id" {
  description = "ID of the PRTG exporter EC2 instance"
  value       = aws_instance.prtg_exporter.id
}

output "exporter_ipv4_address" {
  description = "IPv4 Address of the PRTG exporter instance"
  value       = aws_instance.prtg_exporter.public_ip
}

output "exporter_metrics_url" {
  description = "URL to access Prometheus metrics"
  value       = "http://${aws_instance.prtg_exporter.public_ip}:${var.exporter_port}/metrics"
}

output "exporter_port" {
  description = "Port where metrics are exposed"
  value       = var.exporter_port
}

output "exporter_setup_info" {
  description = "Quick reference for PRTG exporter setup"
  value = <<-EOT
    
    ═══════════════════════════════════════════════════════════
    PRTG Exporter Setup Information
    ═══════════════════════════════════════════════════════════
    
    IPv4 Address: ${aws_instance.prtg_exporter.public_ip}
    Instance ID:  ${aws_instance.prtg_exporter.id}
    
    Metrics Endpoint: http://${aws_instance.prtg_exporter.public_ip}:${var.exporter_port}/metrics
    
    Configuration:
    - PRTG Server: ${var.prtg_server}
    - Exporter Port: ${var.exporter_port}
    
    ═══════════════════════════════════════════════════════════
    
  EOT
}
