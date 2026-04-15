# ============================================================
# monitoring.tf
# ============================================================
# This file sets up the security visibility layer:
#
#   1. S3 Bucket for CloudTrail logs
#   2. CloudTrail (API audit logging)
#   3. GuardDuty (threat detection)
#   4. CloudWatch Dashboard
#   5. CloudWatch Alarms + SNS notifications
# ============================================================


# ============================================================
# 1. S3 BUCKET FOR CLOUDTRAIL LOGS
# ============================================================
# CloudTrail needs an S3 bucket to write logs into.
# This bucket must be:
#   - Private (no public access)
#   - Have a bucket policy allowing CloudTrail to write
#   - Encrypted
# ============================================================

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "secure-3tier-cloudtrail${var.suffix}-${data.aws_caller_identity.current.account_id}"
  # Include account ID in bucket name — S3 names are globally unique
  # This prevents name conflicts with other AWS accounts
  force_destroy = true # Allow terraform destroy to delete the bucket
  # In production: force_destroy = false to protect audit logs

  tags = {
    Name = "cloudtrail-logs"
  }
}

# Block ALL public access — audit logs must never be public
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt all objects in the bucket using our KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.id
    }
  }
}

# Bucket policy — grants CloudTrail service permission to write logs
# Without this policy, CloudTrail can't write to the bucket
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}


# ============================================================
# 2. CLOUDTRAIL
# ============================================================
# CloudTrail records EVERY API call made in your AWS account.
# Who did what, when, from where.
#
# This is the audit log. If something bad happens (breach,
# misconfiguration, accidental deletion), CloudTrail tells
# you exactly what happened and who did it.
#
# include_global_service_events = true captures IAM events
# (logins, role assumptions) which are global, not regional.
#
# enable_log_file_validation = true creates a hash digest
# of each log file. If logs are tampered with, the hash
# won't match — you'll know the logs were modified.
# ============================================================

resource "aws_cloudtrail" "main" {
  name           = "secure-3tier-trail${var.suffix}"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id

  include_global_service_events = true  # Capture IAM, STS events
  is_multi_region_trail         = false # Single region (free tier)
  enable_log_file_validation    = true  # Tamper detection

  # Also send to CloudWatch Logs for real-time alerting
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch_role.arn

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs,
    aws_cloudwatch_log_group.cloudtrail,
    aws_iam_role.cloudtrail_cloudwatch_role,
    aws_iam_role_policy.cloudtrail_cloudwatch_policy,
    aws_s3_bucket_public_access_block.cloudtrail_logs,
    aws_s3_bucket_server_side_encryption_configuration.cloudtrail_logs,
    aws_kms_key.main
  ]
  # Must create bucket policy before CloudTrail
  # otherwise CloudTrail can't write and will error

  tags = {
    Name = "secure-3tier-trail"
  }
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/secure-3tier"
  retention_in_days = 30
}

# IAM role for CloudTrail to write to CloudWatch
resource "aws_iam_role" "cloudtrail_cloudwatch_role" {
  name = "cloudtrail-cloudwatch-role${var.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch_policy" {
  name = "cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}


# ============================================================
# 3. GUARDDUTY
# ============================================================
# GuardDuty is AWS's threat detection service.
# It continuously analyzes:
#   - VPC Flow Logs (unusual network traffic)
#   - CloudTrail (suspicious API calls)
#   - DNS logs (malware callbacks, crypto mining)
#
# It uses ML to detect anomalies and generates "findings"
# (alerts) when it detects threats.
#
# This is literally ONE resource in Terraform.
# There's no reason not to enable it.
# ============================================================

# resource "aws_guardduty_detector" "main" {
#   enable = true

#   datasources {
#     s3_logs {
#       enable = true # Monitor S3 data access
#     }
#     malware_protection {
#       scan_ec2_instance_with_findings {
#         ebs_volumes {
#           enable = true # Scan EC2 disks for malware on findings
#         }
#       }
#     }
#   }

#   tags = {
#     Name = "secure-3tier-guardduty"
#   }
# }


# ============================================================
# 4. SNS TOPIC (for alarm notifications)
# ============================================================
# SNS (Simple Notification Service) is a messaging service.
# We use it to send email alerts when CloudWatch alarms fire.
#
# After deploying, AWS sends a confirmation email to your
# address. YOU MUST CLICK CONFIRM or alarms won't send emails.
# ============================================================

resource "aws_sns_topic" "alarms" {
  name = "secure-3tier-alarms"

  tags = {
    Name = "alarm-notifications"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email # Your email from variables.tf
}


# ============================================================
# 5. CLOUDWATCH ALARMS
# ============================================================
# Alarms watch a metric and trigger when it crosses a threshold.
# When an alarm triggers, it sends a notification to our SNS
# topic, which emails you.
#
# We create 3 alarms:
#   a. EC2 high CPU (app is overloaded)
#   b. ALB unhealthy hosts (instances are failing health checks)
#   c. RDS high CPU (database is under pressure)
# ============================================================

# a. High CPU on EC2
resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  alarm_name          = "ec2-high-cpu"
  alarm_description   = "EC2 CPU utilization above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2       # Must breach threshold 2 times in a row
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120     # Check every 120 seconds
  statistic           = "Average"
  threshold           = 80      # Alert when CPU > 80%

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn] # Also notify when it recovers

  tags = {
    Name = "ec2-high-cpu-alarm"
  }
}

# b. ALB unhealthy hosts — MOST IMPORTANT ALARM
# If this fires, your app is down
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "alb-unhealthy-hosts"
  alarm_description   = "One or more ALB targets are unhealthy"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0 # Alert if even 1 host is unhealthy

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = {
    Name = "alb-unhealthy-hosts-alarm"
  }
}

# c. RDS high CPU
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "rds-high-cpu"
  alarm_description   = "RDS CPU utilization above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = {
    Name = "rds-high-cpu-alarm"
  }
}


# ============================================================
# 6. CLOUDWATCH DASHBOARD
# ============================================================
# A dashboard gives you a visual overview of your system
# in the AWS console. One place to see everything.
# ============================================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "secure-3tier-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          region  = var.aws_region
          title  = "EC2 CPU Utilization"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName",
            aws_autoscaling_group.app.name]
          ]
        }
      },
      {
        type = "metric"
        properties = {
          region  = var.aws_region
          title  = "ALB Request Count"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer",
            aws_lb.main.arn_suffix]
          ]
        }
      },
      {
        type = "metric"
        properties = {
          region  = var.aws_region
          title  = "ALB Healthy/Unhealthy Hosts"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer",
              aws_lb.main.arn_suffix, "TargetGroup",
              aws_lb_target_group.app.arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer",
              aws_lb.main.arn_suffix, "TargetGroup",
              aws_lb_target_group.app.arn_suffix]
          ]
        }
      },
      {
        type = "metric"
        properties = {
          region  = var.aws_region
          title  = "RDS CPU Utilization"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier",
            aws_db_instance.main.id]
          ]
        }
      },
      {
        type = "metric"
        properties = {
          region  = var.aws_region
          title  = "RDS Database Connections"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier",
            aws_db_instance.main.id]
          ]
        }
      }
    ]
  })
}
