mock_provider "aws" {
  mock_resource "aws_lb_listener" { defaults = { arn = "arn:aws:elasticloadbalancing:sa-east-1:123456789012:listener/app/test/0123456789abcdef/0123456789abcdef" } }
  mock_resource "aws_launch_template" { defaults = { id = "lt-0123456789abcdef0" } }
  mock_resource "aws_acm_certificate" { defaults = { arn = "arn:aws:acm:sa-east-1:123456789012:certificate/test", domain_validation_options = [{ domain_name = "api.example.com", resource_record_name = "_test.api.example.com", resource_record_type = "CNAME", resource_record_value = "_test.acm-validations.aws" }] } }
  mock_resource "aws_acm_certificate_validation" { defaults = { certificate_arn = "arn:aws:acm:sa-east-1:123456789012:certificate/test" } }
  mock_resource "aws_lb" { defaults = { arn = "arn:aws:elasticloadbalancing:sa-east-1:123456789012:loadbalancer/app/test/0123456789abcdef", arn_suffix = "app/test/0123456789abcdef" } }
  mock_resource "aws_lb_target_group" { defaults = { arn = "arn:aws:elasticloadbalancing:sa-east-1:123456789012:targetgroup/test/0123456789abcdef", arn_suffix = "targetgroup/test/0123456789abcdef" } }
  mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:sa-east-1:123456789012:test" } }
  mock_resource "aws_autoscaling_group" { defaults = { arn = "arn:aws:autoscaling:sa-east-1:123456789012:autoScalingGroup:test:autoScalingGroupName/test" } }
  mock_resource "aws_ecs_task_definition" { defaults = { arn = "arn:aws:ecs:sa-east-1:123456789012:task-definition/test:1" } }

  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_availability_zones" { defaults = { names = ["sa-east-1a", "sa-east-1c"] } }
  mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
  mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/test" } }
  mock_resource "aws_iam_instance_profile" { defaults = { arn = "arn:aws:iam::123456789012:instance-profile/test" } }
  mock_resource "aws_ecs_cluster" { defaults = { arn = "arn:aws:ecs:sa-east-1:123456789012:cluster/test" } }
  mock_resource "aws_ecr_repository" { defaults = { repository_url = "123456789012.dkr.ecr.sa-east-1.amazonaws.com/test", arn = "arn:aws:ecr:sa-east-1:123456789012:repository/test" } }
  mock_resource "aws_secretsmanager_secret" { defaults = { arn = "arn:aws:secretsmanager:sa-east-1:123456789012:secret:test-123456" } }
  mock_resource "aws_db_instance" { defaults = { master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:sa-east-1:123456789012:secret:database-123456" }] } }
}
variables {
  github_repository         = "JeanRoque0/broto-api-golang"
  api_domain                = ""
  site_url                  = "https://example.com"
  cors_origins              = "https://example.com"
  smtp_from                 = "Broto <sender@example.com>"
  cloudfront_public_key_pem = "-----BEGIN PUBLIC KEY-----\nTEST-ONLY\n-----END PUBLIC KEY-----"
}
run "cost_oriented_bootstrap" {
  command = apply
  assert {
    condition     = aws_ecs_task_definition.app.cpu == "2048" && aws_ecs_task_definition.app.memory == "780" && aws_launch_template.ecs.instance_type == "t3.small"
    error_message = "Requested compute sizing changed."
  }
  assert {
    condition     = aws_ecs_service.api.desired_count == 0 && aws_autoscaling_group.ecs.min_size == 0 && aws_autoscaling_group.ecs.desired_capacity == 0 && length(aws_lb_listener.https) == 0
    error_message = "Bootstrap must wait for capacity-provider association before launching hosts or pulling images."
  }
  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "fixed-response" && aws_lb_listener.http.default_action[0].fixed_response[0].status_code == "503" && length(aws_lb_listener_rule.bootstrap_health) == 1
    error_message = "Without TLS, only health endpoints may be exposed."
  }
  assert {
    condition     = aws_db_instance.main.instance_class == "db.t4g.micro" && aws_db_instance.main.storage_encrypted && !aws_db_instance.main.publicly_accessible && aws_db_instance.main.deletion_protection
    error_message = "Database security/sizing regressed."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.photos.block_public_policy && aws_cloudfront_distribution.photos.default_cache_behavior[0].viewer_protocol_policy == "https-only"
    error_message = "Photo origin/CDN must remain private and HTTPS-only."
  }
  assert {
    condition     = aws_launch_template.ecs.metadata_options[0].http_tokens == "required" && jsondecode(aws_ecs_task_definition.app.container_definitions)[0].readonlyRootFilesystem
    error_message = "Host/container hardening regressed."
  }
}
run "https_with_scaling" {
  command = apply
  variables {
    api_domain             = "api.example.com"
    origin_certificate_arn = "arn:aws:acm:sa-east-1:123456789012:certificate/test"
    max_tasks              = 2
    deploy_enabled         = true
    min_tasks              = 2
    rds_multi_az           = true
  }
  assert {
    condition     = length(aws_lb_listener.https) == 1 && aws_launch_template.ecs.network_interfaces[0].associate_public_ip_address && aws_appautoscaling_target.api[0].min_capacity == 2 && aws_db_instance.main.multi_az
    error_message = "HTTPS/HA variant did not enable the requested topology."
  }
}
