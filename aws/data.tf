resource "aws_ecr_repository" "api" {
  name                 = "${var.name}-api"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  force_delete = false
}
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({ rules = [
    { rulePriority = 1, description = "Keep 30 recent release images", selection = { tagStatus = "tagged", tagPrefixList = ["git-"], countType = "imageCountMoreThan", countNumber = 30 }, action = { type = "expire" } },
    { rulePriority = 2, description = "Remove old untagged images", selection = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 14 }, action = { type = "expire" } }
  ] })
}
resource "aws_s3_bucket" "photos" {
  bucket        = "${var.name}-photos-${local.account}-${var.aws_region}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "photos" {
  bucket                  = aws_s3_bucket.photos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "photos" {
  bucket = aws_s3_bucket.photos.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "photos" {
  bucket = aws_s3_bucket.photos.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_versioning" "photos" {
  bucket = aws_s3_bucket.photos.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_lifecycle_configuration" "photos" {
  bucket = aws_s3_bucket.photos.id
  rule {
    id     = "bounded-recovery"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_s3_bucket_policy" "photos" {
  bucket = aws_s3_bucket.photos.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "cloudfront.amazonaws.com" }, Action = "s3:GetObject", Resource = "${aws_s3_bucket.photos.arn}/photos/*", Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.photos.arn } } }, { Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.photos.arn, "${aws_s3_bucket.photos.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })
}
resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = aws_subnet.database[*].id
}
resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.name}-"
  family      = "postgres17"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name         = "max_connections"
    value        = "50"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "password_encryption"
    value = "scram-sha-256"
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_db_instance" "main" {
  depends_on                      = [aws_cloudwatch_log_group.postgresql]
  identifier                      = var.name
  engine                          = "postgres"
  engine_version                  = var.postgres_version
  instance_class                  = "db.t4g.micro"
  allocated_storage               = 20
  max_allocated_storage           = 50
  storage_type                    = "gp3"
  storage_encrypted               = true
  db_name                         = "broto"
  username                        = "broto_admin"
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  parameter_group_name            = aws_db_parameter_group.main.name
  publicly_accessible             = false
  multi_az                        = var.rds_multi_az
  backup_retention_period         = 7
  backup_window                   = "06:00-07:00"
  maintenance_window              = "sun:07:00-sun:08:00"
  auto_minor_version_upgrade      = true
  allow_major_version_upgrade     = false
  apply_immediately               = false
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-final"
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  performance_insights_enabled    = false
}
# Values are populated outside Terraform so passwords/API keys never enter state.
resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.name}/application"
  recovery_window_in_days = 30
}
resource "aws_secretsmanager_secret" "app_database" {
  name                    = "${var.name}/database-app"
  recovery_window_in_days = 30
}
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name}"
  retention_in_days = 14
}
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/${var.name}/postgresql"
  retention_in_days = 14
}
