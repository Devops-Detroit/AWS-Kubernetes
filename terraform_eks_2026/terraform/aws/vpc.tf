locals {
  # Preserves the original addressing: private 10.0.10/20/30.0/24,
  # public 10.0.40/50/60.0/24.
  private_subnets = {
    for i, az in var.availability_zones : az => cidrsubnet(var.vpc_cidr, 8, 10 + i * 10)
  }

  public_subnets = {
    for i, az in var.availability_zones : az => cidrsubnet(var.vpc_cidr, 8, 40 + i * 10)
  }

  nat_azs = var.single_nat_gateway ? [var.availability_zones[0]] : var.availability_zones
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name = "priv-${each.key}"
    # internal-elb, not elb — the original tagged private subnets as public,
    # which lets the ALB controller place internet-facing LBs in them.
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = {
    Name                     = "pub-${each.key}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  # `vpc = true` was removed in AWS provider 5.0; `domain` replaced it.
  domain = "vpc"

  tags = {
    Name = "nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = {
    Name = "nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.nat[local.nat_azs[0]].id : aws_nat_gateway.nat[each.key].id
  }

  tags = {
    Name = "private-${each.key}"
  }
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}
