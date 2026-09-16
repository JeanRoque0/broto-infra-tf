output "api_url" { value = local.public_url }
output "github_actions_variables" {
  value = {
    AWS_REGION            = var.aws_region, AWS_DEPLOY_ROLE_ARN = aws_iam_role.deploy.arn,
    ECR_REPOSITORY        = aws_ecr_repository.api.name, ECR_REGISTRY = split("/", aws_ecr_repository.api.repository_url)[0],
    ECS_CLUSTER           = aws_ecs_cluster.main.name, ECS_SERVICE = aws_ecs_service.api.name,
    ECS_TASK_FAMILY       = aws_ecs_task_definition.app.family, ECS_MIGRATION_FAMILY = aws_ecs_task_definition.migrate.family,
    ECS_CAPACITY_PROVIDER = aws_ecs_capacity_provider.ec2.name,
    DB_APP_SECRET_ARN     = aws_secretsmanager_secret.app_database.arn,
    ECS_MIN_TASKS         = tostring(var.min_tasks)
  }
}
output "application_secret_arn" { value = aws_secretsmanager_secret.app.arn }
output "photos_bucket" { value = aws_s3_bucket.photos.id }
output "database_endpoint" { value = aws_db_instance.main.address }
output "capacity_warning" { value = "Each 2048-CPU task occupies one t3.small. Default is single-task and Single-AZ RDS; min_tasks=2 and rds_multi_az=true increase availability and cost." }

output "alb_hostname" { value = aws_lb.api.dns_name }
output "https_ready" { value = var.origin_certificate_arn != "" }
