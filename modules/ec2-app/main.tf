# Security groups
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-${var.environment}-alb-sg"
  description = "ALB SG"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-alb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count             = var.enable_https ? 1 : 0
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS"
}

resource "aws_vpc_security_group_egress_rule" "alb_egress_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-${var.environment}-app-sg"
  description = "App SG"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-app-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  description                  = "App from ALB"
}

# SSH access: create one rule per CIDR
resource "aws_vpc_security_group_ingress_rule" "app_ssh_cidrs" {
  for_each          = toset(var.ssh_ingress_cidrs)
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH"
}

resource "aws_vpc_security_group_egress_rule" "app_egress_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# IAM: role + instance profile
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name_prefix}-${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

# Basic managed policy for SSM + CloudWatch agent
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "cw" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-${var.environment}-instance-profile"
  role = aws_iam_role.ec2.name
  tags = var.tags
}

# ALB + TG + Listeners
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-${var.environment}-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids_for_alb
  security_groups    = [aws_security_group.alb.id]
  idle_timeout       = 60
  tags               = var.tags
}

resource "aws_lb_target_group" "app" {
  name        = "${var.name_prefix}-${var.environment}-tg"
  vpc_id      = var.vpc_id
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "instance"
  health_check {
    path = var.health_check_path
  }
  tags = var.tags
}

resource "aws_lb_listener" "http" {
  count             = var.enable_https ? 0 : 1
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# If TLS is enabled, create HTTPS listener and redirect HTTP to HTTPS
resource "aws_lb_listener" "http_redirect" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# If TLS is enabled, create Route53 record for ALB
resource "aws_route53_record" "public_alb_dns_A_record" {
  count           = var.enable_https ? 1 : 0
  zone_id         = var.route53_zone_id
  name            = var.domain_name
  type            = "A"
  allow_overwrite = true 
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  } 
}

# ACM Certificate and Validation for optional TLS
resource "aws_acm_certificate" "this" {
  count             = var.enable_https ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags              = var.tags
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_https ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}
  
  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.enable_https ? 1 : 0
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ALB listener, reference the validated cert if TLS is enabled
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this[count.index].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}


# Launch template with fry variables injected via user_data
locals {
  fry_vars = jsonencode({
    site_title = var.site_title
    message    = var.message
  })

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    mkdir -p /etc/fry
    cat >/etc/fry/vars.json <<'JSON'
    ${local.fry_vars}
    JSON
    systemctl daemon-reload
    systemctl enable fry.service || true
    systemctl start fry.service || true
  EOF
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-${var.environment}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.create_ssh_key ? aws_key_pair.this[0].key_name : var.ssh_key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-ec2" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ASG across private subnets
resource "aws_autoscaling_group" "this" {
  name                      = "${var.name_prefix}-${var.environment}-asg"
  desired_capacity          = 2
  min_size                  = 2
  max_size                  = 2
  health_check_type         = "ELB"
  health_check_grace_period = 60
  vpc_zone_identifier       = var.private_subnet_ids_for_asg

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-${var.environment}-ec2"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
