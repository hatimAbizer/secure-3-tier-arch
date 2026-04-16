# outputs.tf

output "app_url" {
  description = "Your app — open this in a browser"
  value       = "http://${aws_lb.main.dns_name}"
}

output "health_check_url" {
  description = "Should return {status:ok, db:connected}"
  value       = "http://${aws_lb.main.dns_name}/health"
}

output "artifact_bucket_name" {
  description = "Upload app.zip here before terraform apply"
  value       = aws_s3_bucket.artifacts.bucket
}

output "rds_endpoint" {
  description = "RDS hostname — stored in SSM, app reads it from there"
  value       = aws_db_instance.main.address
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard — screenshot this for LinkedIn"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
