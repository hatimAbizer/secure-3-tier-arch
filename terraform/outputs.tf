# outputs.tf
# Printed to terminal after terraform apply.

output "app_url" {
  description = "Open this in your browser to see the Todo app"
  value       = "http://${aws_lb.main.dns_name}"
}

output "health_check_url" {
  description = "Verify the app and DB are connected"
  value       = "http://${aws_lb.main.dns_name}/health"
}

output "artifact_bucket_name" {
  description = "Add this as S3_BUCKET in GitHub Secrets"
  value       = aws_s3_bucket.artifacts.bucket
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "RDS address (stored in SSM automatically — app reads from there)"
  value       = aws_db_instance.main.address
}

output "cloudwatch_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
