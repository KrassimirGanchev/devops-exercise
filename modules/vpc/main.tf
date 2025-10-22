

locals {
  azs = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 2)

  # Build public/private subnet descriptors:
  public_subnets = flatten([
    for az_i, az in local.azs : [
      for i in range(var.subnets_per_az) : {
        key    = "${az}-public-${i}"
        az     = az
        index  = az_i * (var.subnets_per_az * 2) + i
        public = true
      }
    ]
  ])
  private_subnets = flatten([
    for az_i, az in local.azs : [
      for i in range(var.subnets_per_az) : {
        key    = "${az}-private-${i}"
        az     = az
        index  = az_i * (var.subnets_per_az * 2) + (var.subnets_per_az + i)
        public = false
      }
    ]
  ])

  public_map  = { for s in local.public_subnets  : s.key => s }
  private_map = { for s in local.private_subnets : s.key => s }
}

# VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${var.environment}-vpc"
  })
}

# IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-igw" })
}

# Subnets
resource "aws_subnet" "public" {
  for_each                = local.public_map
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value.index) # /20 blocks
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${var.environment}-${each.value.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each                = local.private_map
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value.index) # /20 blocks
  map_public_ip_on_launch = false
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${var.environment}-${each.value.key}"
    Tier = "private"
  })
}

# NAT per AZ (placed in the first public subnet of each AZ)
resource "aws_eip" "nat" {
  for_each = toset(local.azs)
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-eip-nat-${each.key}" })
}

resource "aws_nat_gateway" "nat" {
  for_each      = toset(local.azs)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public["${each.key}-public-0"].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-nat-${each.key}" })
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-rtb-public" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = toset(local.azs)
  vpc_id   = aws_vpc.this.id
  tags     = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-rtb-private-${each.key}" })
}

resource "aws_route" "private_default" {
  for_each               = toset(local.azs)
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[each.key].id
}

# Associate all private subnets in an AZ to that AZ's private route table
resource "aws_route_table_association" "private_assoc" {
  for_each       = { for k, s in aws_subnet.private : k => s if can(regex("^(.*)-private-\\d+$", k)) }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.value.availability_zone].id
}

# Security group for VPC endpoints
resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-${var.environment}-endpoints-sg"
  description = "Allow HTTP/HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id
  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-endpoints-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_http" {
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS"
}

resource "aws_vpc_security_group_egress_rule" "endpoints_egress_all" {
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# S3 Gateway endpoint (attach to private RTs)
resource "aws_vpc_endpoint" "s3" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = [for az in local.azs : aws_route_table.private[az].id]
  tags                = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-s3-endpoint" })
}

# SSM interface endpoint
locals {
  # 1. Group private subnets (from the resource map) by AZ
  private_subnets_by_az = {
    # aws_subnet.private is a map of subnet objects created by the resource block
    for k, s in aws_subnet.private : s.availability_zone => s... # Group by AZ, collect subnet objects
  }

  # 2. Select the ID of the *first* subnet found in each AZ's list
  endpoint_subnet_ids = values({
    # Create a map containing only the first subnet object for each AZ
    for az, subnets in local.private_subnets_by_az : az => subnets[0]
  })[*].id # Extract the IDs from the resulting list of subnet objects
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-ssm-endpoint" })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-ssmmessages-endpoint" })
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-ec2messages-endpoint" })
}
