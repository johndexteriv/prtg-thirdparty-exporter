terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets in availability zones
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get subnet details - using the first subnet ID from the list
data "aws_subnet" "default" {
  id = tolist(data.aws_subnets.default.ids)[0]
}

# Security group for SNMP monitoring
resource "aws_security_group" "prtg_snmp" {
  name        = "prtg-snmp-monitoring"
  description = "Security group for PRTG SNMP monitoring"
  vpc_id      = data.aws_vpc.default.id

  # Allow SNMP from specified CIDR (configurable via variable)
  ingress {
    description = "SNMP UDP"
    from_port   = 161
    to_port     = 161
    protocol    = "udp"
    cidr_blocks = [var.allowed_snmp_cidr]
  }

  # Allow SSH access (for management)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prtg-snmp-monitoring"
  }
}

# IAM role for EC2 instance (optional, for CloudWatch or other AWS services)
resource "aws_iam_role" "ec2_role" {
  name = "prtg-monitoring-ec2-role"

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
    Name = "prtg-monitoring-ec2-role"
  }
}

# Attach SSM managed policy (required for EC2 Instance Connect and Systems Manager)
resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "prtg-monitoring-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 instance for PRTG SNMP monitoring
resource "aws_instance" "prtg_monitoring" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids = [aws_security_group.prtg_snmp.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = "prtg-exporter-key"
  
  user_data = file("${path.module}/../config/user_data.sh")

  tags = {
    Name = "prtg-snmp-monitoring-host"
  }
}

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Output the instance information
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.prtg_monitoring.id
}

output "ipv4_address" {
  description = "IPv4 Address to use in PRTG (Public IP)"
  value       = aws_instance.prtg_monitoring.public_ip != null ? aws_instance.prtg_monitoring.public_ip : "Instance may not have public IP yet"
}

output "instance_public_ip" {
  description = "Public IPv4 address of the EC2 instance"
  value       = aws_instance.prtg_monitoring.public_ip
}

output "instance_private_ip" {
  description = "Private IPv4 address of the EC2 instance"
  value       = aws_instance.prtg_monitoring.private_ip
}

output "snmp_community" {
  description = "SNMP community string (default: public)"
  value       = "public"
  sensitive   = false
}

output "prtg_setup_info" {
  description = "Quick reference for PRTG sensor setup"
  value = <<-EOT
    
    ═══════════════════════════════════════════════════════════
    PRTG Sensor Setup Information
    ═══════════════════════════════════════════════════════════
    
    IPv4 Address: ${aws_instance.prtg_monitoring.public_ip}
    Private IP:   ${aws_instance.prtg_monitoring.private_ip}
    Instance ID:  ${aws_instance.prtg_monitoring.id}
    
    SNMP Settings:
    - Version:      2c
    - Community:    public
    - Port:         161 (UDP)
    
    ═══════════════════════════════════════════════════════════
    
  EOT
}
