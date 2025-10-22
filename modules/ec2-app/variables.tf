variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "environment" {
  description = "Environment tag (e.g., staging)"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids_for_alb" {
  description = "Public subnets for ALB (one per AZ)"
  type        = list(string)
}

variable "private_subnet_ids_for_asg" {
  description = "Private subnets for ASG (one per AZ)"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID produced by Packer"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_name" {
  description = "Optional EC2 key pair name for SSH (if not using create_ssh_key)"
  type        = string
  default     = null
}

variable "create_ssh_key" {
  description = "Create a new SSH key pair with Terraform and there is no pre-existing key to be used"
  type        = bool
  default     = false
}

variable "ssh_ingress_cidrs" {
  description = "CIDRs allowed to SSH to instances"
  type        = list(string)
  default     = ["0.0.0.0/0"] // tighten in real use
}

variable "app_port" {
  description = "Port exposed by nginx"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "ALB target group health check path"
  type        = string
  default     = "/"
}

variable "site_title" {
  description = "Title rendered by fry role"
  type        = string
  default     = "Staging App"
}

variable "message" {
  description = "Message rendered by fry role"
  type        = string
  default     = "Hello from ASG instance"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# TLS - optional
variable "domain_name" {
  description = "Domain for ACM certificate"
  type        = string
  default     = ""
}
variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID for DNS validation"
  type        = string
  default     = ""
}
variable "enable_https" {
  description = "Enable HTTPS"
  type        = bool
  default     = false
}

# Bastion - optional
variable "enable_bastion" {
  description = "Enable bastion host for SSH access"
  type        = bool
  default     = false
}
variable "bastion_ami_id" {
  description = "AMI ID for bastion (use same region's Amazon Linux 2023)"
  type        = string
  default     = "ami-043fae54adbfa56c1" // Amazon Linux 2023 in us-east-1
}
variable "bastion_instance_type" {
  description = "Instance type for bastion"
  type        = string
  default     = "t3.micro"
}
variable "bastion_ingress_cidr" {
  description = "Your IP CIDR to SSH to bastion"
  type        = string
  default     = "0.0.0.0/0" // Thighten this in production
}