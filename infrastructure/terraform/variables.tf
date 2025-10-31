variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "snmp_community" {
  description = "SNMP community string (default: public)"
  type        = string
  default     = "public"
  sensitive   = true
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to the instance"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_snmp_cidr" {
  description = "CIDR block allowed to access SNMP"
  type        = string
  default     = "0.0.0.0/0"
}

