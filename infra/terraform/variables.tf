variable "aws_region" {
  description = "AWS region for every resource in this stack"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Tag applied to all resources (demo/staging/production)"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Prefix used for all resource names"
  type        = string
  default     = "aws-deployment-demo"
}

variable "vpc_cidr" {
  description = "CIDR block of the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block of the single public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type. Keep a Free Tier eligible type (t2.micro or t3.micro)."
  type        = string
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.5/32). Port 22 is open ONLY to this range."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "ssh_allowed_cidr must be a valid CIDR, e.g. 203.0.113.5/32."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key material for the EC2 key pair used by SSH deployments"
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the SNS alert topic (must confirm the subscription email)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository (owner/repo) allowed to assume the CI deploy role"
  type        = string
  default     = "Khushigupta1112/aws-deployment-pipeline"
}

variable "log_retention_days" {
  description = "Days before deployment logs in S3 expire (cost control)"
  type        = number
  default     = 90
}

variable "cpu_alarm_threshold" {
  description = "CloudWatch CPU alarm threshold in percent"
  type        = number
  default     = 70
}
