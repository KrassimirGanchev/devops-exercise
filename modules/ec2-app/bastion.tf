# Bastion host resources (optional)
resource "aws_security_group" "bastion" {
  count       = var.enable_bastion ? 1 : 0
  name        = "${var.name_prefix}-${var.environment}-bastion-sg"
  description = "Bastion host SG"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-bastion-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  count             = var.enable_bastion ? 1 : 0
  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = var.bastion_ingress_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from admin"
}

resource "aws_vpc_security_group_egress_rule" "bastion_egress" {
  count             = var.enable_bastion ? 1 : 0
  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "bastion" {
  count                       = var.enable_bastion ? 1 : 0
  ami                         = var.bastion_ami_id
  instance_type               = var.bastion_instance_type
  subnet_id                   = var.public_subnet_ids_for_alb[0]
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  key_name                    = var.create_ssh_key ? aws_key_pair.this[0].key_name : var.ssh_key_name
  associate_public_ip_address = true
  tags                        = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-bastion" })
}

# Allow SSH from bastion to app instances
resource "aws_vpc_security_group_ingress_rule" "app_ssh_from_bastion" {
  count                        = var.enable_bastion ? 1 : 0
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.bastion[0].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  description                  = "SSH from bastion"
}