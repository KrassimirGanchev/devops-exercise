output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "bastion_public_ip" {
  value       = var.enable_bastion ? aws_instance.bastion[0].public_ip : null
  description = "Public IP of bastion host for SSH access"
}

output "ssh_private_key_path" {
  value       = var.create_ssh_key ? local_file.private_key[0].filename : "Use your own key: ${var.ssh_key_name}"
  description = "Path to the SSH private key file"
}

output "ssh_command" {
  value       = var.enable_bastion && var.create_ssh_key ? "ssh -i ${local_file.private_key[0].filename} ec2-user@${aws_instance.bastion[0].public_ip}" : null
  description = "SSH command to connect to bastion"
}
