# compute.tf
# ALB, Launch Template, Auto Scaling Group

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Application Load Balancer ──────────────────────────────
# Public entry point. Internet → ALB → EC2.
# Lives in both public subnets across 2 AZs.
resource "aws_lb" "main" {
  name               = "secure-3tier-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags               = { Name = "secure-3tier-alb" }
}

# ── Target Group ───────────────────────────────────────────
# The pool of EC2 instances the ALB sends traffic to.
# ALB health-checks /health every 30s.
# If an instance fails → ALB stops sending it traffic.
resource "aws_lb_target_group" "app" {
  name     = "app-target-group"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  deregistration_delay = 300

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "app-target-group" }
}

# ── ALB Listener ───────────────────────────────────────────
# Listens on port 80, forwards everything to the target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── Launch Template ────────────────────────────────────────
# Blueprint for EC2 instances.
# userdata.sh installs Node.js and pulls secrets from SSM.
# App code is deployed separately via the CI/CD pipeline.
resource "aws_launch_template" "app" {
  name_prefix   = "secure-3tier-app-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true         # No direct internet access
    security_groups             = [aws_security_group.app.id]
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    region            = var.aws_region
    app_port          = var.app_port
    artifact_bucket   = aws_s3_bucket.artifacts.id
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp2"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "secure-3tier-instance" }
  }

  lifecycle { create_before_destroy = true }
}

# ── Auto Scaling Group ─────────────────────────────────────
# Manages EC2 instances: launches, health-checks, replaces.
# health_check_type = "ELB" means if the app's /health
# endpoint fails, ASG replaces the instance automatically.
resource "aws_autoscaling_group" "app" {
  name                      = "secure-3tier-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180  # Give the app 3 min to start before health checks begin

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "secure-3tier-app"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}

# ── Auto Scaling Policy ────────────────────────────────────
# Add instances when average CPU across the group exceeds 70%.
resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
