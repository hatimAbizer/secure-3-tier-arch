resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/myapp/db/password"
  description = "RDS MySQL master password"
  type        = "SecureString"
  value       = random_password.db_password.result
  key_id      = aws_kms_key.main.arn
  tags        = { Name = "db-password" }
}

resource "aws_ssm_parameter" "db_host" {
  name        = "/myapp/db/host"
  description = "RDS endpoint hostname"
  type        = "String"
  value       = aws_db_instance.main.address
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/myapp/db/name"
  type  = "String"
  value = var.db_name
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/myapp/db/username"
  type  = "String"
  value = var.db_username
}

resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = { Name = "main-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier     = "secure-3tier-db"
  db_name        = var.db_name
  engine         = "mysql"
  engine_version = "8.0"

  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2"

  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  multi_az          = false
  storage_encrypted = true

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  tags = { Name = "secure-3tier-mysql" }
}
