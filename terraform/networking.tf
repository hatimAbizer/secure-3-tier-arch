# ============================================================
# networking.tf
# ============================================================
# This file builds the entire network foundation.
# Everything else (EC2, RDS, ALB) sits on top of this.
#
# ORDER OF CREATION:
# 1. VPC (the private network boundary)
# 2. Subnets (subdivisions inside the VPC)
# 3. Internet Gateway (the door to the internet)
# 4. Route Tables (the GPS — tells traffic where to go)
# 5. Route Table Associations (connects subnets to route tables)
# ============================================================


# ============================================================
# 1. VPC
# ============================================================
# A VPC (Virtual Private Cloud) is your private, isolated
# network inside AWS. Nothing can get in or out unless
# you explicitly allow it.
#
# enable_dns_hostnames = true means EC2 instances get
# a DNS name (e.g. ec2-xx.compute.amazonaws.com).
# This is needed for SSM to work correctly.
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "secure-3tier-vpc"
  }
}


# ============================================================
# 2. SUBNETS
# ============================================================
# Subnets are IP ranges within your VPC.
# We create 4:
#   - 2 public  (EC2 + ALB) — one per AZ
#   - 2 private (RDS only)  — one per AZ
#
# "Public" doesn't mean the internet can reach it freely.
# It means it has a route to the Internet Gateway.
# Our EC2s are in public subnets but have NO public IP —
# so they're still unreachable directly from the internet.
#
# availability_zone uses data sources (see bottom of file)
# to get the actual AZ names for your region dynamically.
# ============================================================

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false # SECURITY: No automatic public IPs

  tags = {
    Name = "public-subnet-a"
    Tier = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "public-subnet-b"
    Tier = "public"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-subnet-a"
    Tier = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-subnet-b"
    Tier = "private"
  }
}


# ============================================================
# 3. INTERNET GATEWAY
# ============================================================
# The Internet Gateway is the bridge between your VPC
# and the public internet. Without it, nothing in your
# VPC can reach or be reached from the internet.
#
# One IGW per VPC. That's it.
# ============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}


# ============================================================
# 4. ROUTE TABLES
# ============================================================
# A route table is like a GPS for network traffic.
# It says: "if traffic is going to X, send it via Y"
#
# PUBLIC route table:
#   - Local traffic (10.0.0.0/16) → stays in VPC
#   - Everything else (0.0.0.0/0) → goes to IGW (internet)
#
# PRIVATE route table:
#   - Local traffic only
#   - No route to internet — RDS is completely isolated
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"        # All traffic...
    gateway_id = aws_internet_gateway.main.id # ...goes to IGW
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  # No routes added = local VPC traffic only
  # RDS can only be reached from inside the VPC

  tags = {
    Name = "private-rt"
  }
}


# ============================================================
# 5. ROUTE TABLE ASSOCIATIONS
# ============================================================
# Route tables don't do anything until you attach them
# to subnets. This step connects each subnet to its
# correct route table.
#
# Think of it as: "this subnet follows these GPS rules"
# ============================================================

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}


# ============================================================
# VPC FLOW LOGS
# ============================================================
# Flow Logs capture all IP traffic going in/out of your VPC.
# This is critical for security — if something suspicious
# happens, Flow Logs tell you exactly what connected to what.
#
# We log to CloudWatch Logs so you can search them easily.
# The IAM role gives Flow Logs permission to write to CW.
# ============================================================

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL" # Capture ACCEPT and REJECT traffic
  iam_role_arn    = aws_iam_role.flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = {
    Name = "vpc-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flowlogs${var.suffix}"
  retention_in_days = 30 # Keep logs for 30 days then auto-delete

  tags = {
    Name = "vpc-flow-logs-group"
  }
}


# ============================================================
# DATA SOURCES
# ============================================================
# Data sources let Terraform READ existing AWS information
# instead of creating something new.
#
# aws_availability_zones fetches the list of AZs available
# in your region. So names[0] = first AZ, names[1] = second.
# This makes the code work in ANY region without hardcoding
# AZ names like "us-east-1a".
# ============================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# Fetches your AWS account ID dynamically
# Used in IAM policies to build ARNs correctly
data "aws_caller_identity" "current" {}
