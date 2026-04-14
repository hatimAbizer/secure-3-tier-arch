# security.tf
# Security Groups, KMS, IAM, S3 artifact bucket

# ── Security Groups ────────────────────────────────────────
# The chain: ALB SG → App SG → DB SG
# Each layer can ONLY talk to the one below it.

resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "ALB accepts HTTP from internet"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "app" {
  name = "app-sg"
  description = "App accepts HTTP from ALB, and talks to DB"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group" "db" {
  name = "db-sg"
  description = "DB accepts MySQL from App only"
  vpc_id = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  from_port = 80
  to_port   = 80
  ip_protocol  = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port = var.app_port
  to_port   = var.app_port
  ip_protocol  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_outbound_https" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

# ── KMS Key ────────────────────────────────────────────────
resource "aws_kms_key" "main" {
  description             = "Encrypts SSM secrets and RDS storage"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { Name = "secure-3tier-kms" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/secure-3tier-app"
  target_key_id = aws_kms_key.main.id
}

# ── IAM Role for EC2 ───────────────────────────────────────
# Least privilege: only what the instance actually needs.
resource "aws_iam_role" "ec2_role" {
  name = "ec2-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Read DB secrets from SSM (used by userdata.sh on boot)
resource "aws_iam_role_policy" "ssm_secrets" {
  name = "ssm-secrets"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/myapp/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

# Download app artifact from S3 (used by CI/CD deploy step)
resource "aws_iam_role_policy" "s3_artifact" {
  name = "s3-artifact"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.artifacts.arn}/*"
    }]
  })
}

# CloudWatch logs and metrics
resource "aws_iam_role_policy" "cloudwatch" {
  name = "cloudwatch"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "cloudwatch:PutMetricData"]
      Resource = "*"
    }]
  })
}

# SSM core — allows CI/CD to run deploy commands on EC2 without SSH
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-app-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# ── IAM Role for VPC Flow Logs ────────────────────────────
resource "aws_iam_role" "flow_logs_role" {
  name = "vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs_policy" {
  name = "flow-logs-policy"
  role = aws_iam_role.flow_logs_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = "*"
    }]
  })
}

# ── S3 Artifact Bucket ─────────────────────────────────────
# CI/CD uploads the zipped app here.
# EC2 downloads it during deployment.
resource "aws_s3_bucket" "artifacts" {
  bucket        = "secure-3tier-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "app-artifacts" }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
