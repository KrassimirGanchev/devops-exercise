# Generate SSH key pair using Terraform
resource "tls_private_key" "ssh" {
  count     = var.create_ssh_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  count      = var.create_ssh_key ? 1 : 0
  key_name   = "${var.name_prefix}-${var.environment}-key"
  public_key = tls_private_key.ssh[0].public_key_openssh
  tags       = var.tags
}

# Save private key locally
resource "local_file" "private_key" {
  count           = var.create_ssh_key ? 1 : 0
  content         = tls_private_key.ssh[0].private_key_pem
  filename        = pathexpand("~/.ssh/${var.name_prefix}-${var.environment}-key.pem")
  file_permission = "0400"
}
