resource "aws_ecs_cluster" "main" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}
resource "aws_launch_template" "ecs" {
  name_prefix            = "${var.name}-"
  image_id               = nonsensitive(data.aws_ssm_parameter.ecs_ami.value)
  instance_type          = "t3.small"
  update_default_version = true
  iam_instance_profile { arn = aws_iam_instance_profile.host.arn }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  credit_specification { cpu_credits = "standard" }
  monitoring { enabled = false }
  network_interfaces {
    associate_public_ip_address = !var.private_compute
    security_groups             = [aws_security_group.hosts.id]
    delete_on_termination       = true
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  user_data = base64encode(templatefile("${path.module}/user-data.sh.tftpl", { cluster = aws_ecs_cluster.main.name }))
  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-ecs" }
  }
}
resource "aws_autoscaling_group" "ecs" {
  name                      = "${var.name}-ecs"
  min_size                  = 1
  max_size                  = var.max_tasks + 1
  desired_capacity          = 1
  vpc_zone_identifier       = var.private_compute ? aws_subnet.compute[*].id : aws_subnet.public[*].id
  protect_from_scale_in     = true
  health_check_type         = "EC2"
  health_check_grace_period = 300
  default_instance_warmup   = 180
  launch_template {
    id      = aws_launch_template.ecs.id
    version = tostring(aws_launch_template.ecs.latest_version)
  }
  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
  lifecycle { ignore_changes = [desired_capacity] }
  depends_on = [aws_route.internet, aws_route.nat, aws_iam_role_policy_attachment.host_ecs, aws_iam_role_policy_attachment.host_ssm]
}
resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.name}-ec2"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"
    managed_draining               = "ENABLED"
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
      instance_warmup_period    = 180
    }
  }
}
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 1
  }
}
locals {
  common_environment = {
    HTTP_ADDR  = ":8080", AWS_REGION = var.aws_region,
    DB_HOST    = aws_db_instance.main.address, DB_PORT = "5432", DB_NAME = "broto", DB_SSLMODE = "verify-full", DB_SSLROOTCERT = "/etc/ssl/certs/ca-certificates.crt",
    GOMAXPROCS = "2", GOMEMLIMIT = "600MiB"
  }
  application_environment = merge(local.common_environment, {
    DB_USER             = "broto_app", DB_MAX_CONNS = tostring(local.db_pool), AUTO_MIGRATE = "false", MAX_CONCURRENT_REQUESTS = "16",
    PUBLIC_URL          = "https://${var.api_domain}", SITE_URL = var.site_url, CORS_ORIGINS = var.cors_origins,
    CLOUDFRONT_URL      = "https://${aws_cloudfront_distribution.photos.domain_name}", CLOUDFRONT_KEY_ID = aws_cloudfront_public_key.photos.id,
    STORAGE_BUCKET      = aws_s3_bucket.photos.id, STORAGE_QUOTA_BYTES = "5368709120",
    TRUSTED_PROXY_CIDRS = join(",", aws_subnet.public[*].cidr_block),
    DEV_AUTO_CONFIRM    = "false", SMTP_HOST = var.smtp_host, SMTP_PORT = "587", SMTP_FROM = var.smtp_from, SMTP_MIN_INTERVAL_SECONDS = "60",
    ANTHROPIC_MODEL     = var.anthropic_model, CHAT_MODEL = var.chat_model, ANTHROPIC_EFFORT = var.anthropic_effort, CHAT_MAX_TOKENS = "2048",
    GOOGLE_AUTH_ENABLED = tostring(var.google_enabled), GOOGLE_CLIENT_ID = var.google_client_id,
    GOOGLE_REDIRECT_URL = "https://${var.api_domain}/v1/auth/google/callback", GOOGLE_RETURN_URLS = var.google_return_urls
  })
  log_configuration = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.api.name, awslogs-region = var.aws_region, awslogs-stream-prefix = "ecs", mode = "non-blocking", max-buffer-size = "4m" } }
}
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name}-api"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = tostring(local.task_cpu)
  memory                   = tostring(local.task_memory)
  execution_role_arn       = aws_iam_role.execution["app"].arn
  task_role_arn            = aws_iam_role.task.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name            = "api", image = local.image, essential = true, cpu = local.task_cpu, memory = local.task_memory, memoryReservation = 640,
    user            = "10001:10001", readonlyRootFilesystem = true, privileged = false,
    linuxParameters = { capabilities = { drop = ["ALL"] } }, dockerSecurityOptions = ["no-new-privileges"],
    stopTimeout     = 120,
    portMappings    = [{ containerPort = 8080, hostPort = 0, protocol = "tcp" }],
    healthCheck     = { command = ["CMD", "/broto-api", "healthcheck"], interval = 30, timeout = 3, retries = 3, startPeriod = 30 },
    environment     = [for key, value in local.application_environment : { name = key, value = value }],
    secrets = concat([{ name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.app_database.arn}:password::" }],
    [for key in ["SIGNING_KEY", "ANTHROPIC_API_KEY", "SMTP_USER", "SMTP_PASSWORD", "GOOGLE_CLIENT_SECRET", "CLOUDFRONT_PRIVATE_KEY"] : { name = key, valueFrom = "${aws_secretsmanager_secret.app.arn}:${key}::" }]),
    logConfiguration = local.log_configuration
  }])
}
resource "aws_ecs_task_definition" "migrate" {
  family                   = "${var.name}-migrate"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution["migrate"].arn
  container_definitions = jsonencode([{
    name             = "migrate", image = local.image, essential = true, cpu = 256, memory = 512, command = ["migrate"],
    user             = "10001:10001", readonlyRootFilesystem = true, privileged = false, stopTimeout = 120,
    linuxParameters  = { capabilities = { drop = ["ALL"] } }, dockerSecurityOptions = ["no-new-privileges"],
    environment      = [for key, value in merge(local.common_environment, { DB_USER = "broto_admin", GOMEMLIMIT = "400MiB" }) : { name = key, value = value }],
    secrets          = [{ name = "DB_PASSWORD", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" }, { name = "APP_DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.app_database.arn}:password::" }],
    logConfiguration = local.log_configuration
  }])
}
resource "aws_ecs_service" "api" {
  name            = var.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.deploy_enabled ? var.min_tasks : 0
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  health_check_grace_period_seconds = 90
  enable_execute_command            = false
  enable_ecs_managed_tags           = true
  propagate_tags                    = "SERVICE"
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8080
  }
  lifecycle { ignore_changes = [task_definition, desired_count] }
  depends_on = [aws_lb_listener.https, aws_ecs_cluster_capacity_providers.main, aws_iam_role_policy.execution]
}
resource "aws_appautoscaling_target" "api" {
  count              = var.deploy_enabled ? 1 : 0
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "cpu" {
  count              = var.deploy_enabled ? 1 : 0
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api[0].resource_id
  scalable_dimension = aws_appautoscaling_target.api[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.api[0].service_namespace
  target_tracking_scaling_policy_configuration {
    target_value       = 55
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification { predefined_metric_type = "ECSServiceAverageCPUUtilization" }
  }
}
