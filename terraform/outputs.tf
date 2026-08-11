output "application_url" {
  description = "Public entry point."
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "Image destination for the pipeline."
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "Cluster the pipeline deploys into."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Service the pipeline updates."
  value       = aws_ecs_service.app.name
}

output "task_family" {
  description = "Task definition family the pipeline registers new revisions of."
  value       = aws_ecs_task_definition.app.family
}

output "github_actions_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.github_deploy.arn
}

output "log_group_name" {
  description = "Where both containers write. Query trace_id here."
  value       = aws_cloudwatch_log_group.app.name
}

output "database_endpoint" {
  description = "RDS endpoint. Reachable only from the application security group."
  value       = aws_db_instance.main.endpoint
}

output "database_secret_arn" {
  description = "Secrets Manager entry holding the connection string."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "xray_console_url" {
  description = "Trace map for this service."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#xray:service-map"
}

output "logs_console_url" {
  description = "Log group, with the saved trace-id query available in Insights."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.app.name, "/", "$252F")}"
}
