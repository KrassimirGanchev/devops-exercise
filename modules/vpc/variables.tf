variable "name_prefix" {
  description = "Name prefix for VPC resources"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment tag (e.g., staging)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "172.16.0.0/16"
}

variable "azs" {
  description = "List of 2 availability zones. If empty, first two AZs will be used."
  type        = list(string)
  default     = []
}

variable "subnets_per_az" {
  description = "Number of public and private subnets per AZ (defaults to 2 of each per AZ)."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
