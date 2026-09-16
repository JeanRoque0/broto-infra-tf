variable "aws_region" {
  type    = string
  default = "sa-east-1"
}
variable "name" {
  type    = string
  default = "broto-prod"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,22}$", var.name))
    error_message = "Use 3..23 lowercase letters, numbers or hyphens."
  }
}
variable "github_repository" {
  type        = string
  description = "Future GitHub repository: OWNER/broto-api."
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use OWNER/REPOSITORY, without URL or wildcard."
  }
}
variable "github_environment" {
  type    = string
  default = "production"
}
variable "github_oidc_provider_arn" {
  type        = string
  default     = ""
  description = "Existing GitHub OIDC provider ARN; leave empty to create it once per AWS account."
}
variable "api_domain" {
  type        = string
  default     = ""
  description = "Optional future Cloudflare DNS name, e.g. api.example.com."
}
variable "origin_certificate_arn" {
  type        = string
  default     = ""
  description = "ACM certificate ARN in sa-east-1 for the future API domain (public or imported Cloudflare Origin CA). Empty keeps only health endpoints public over HTTP."
  validation {
    condition     = var.origin_certificate_arn == "" || (var.api_domain != "" && startswith(var.origin_certificate_arn, "arn:aws:acm:"))
    error_message = "HTTPS requires api_domain and an ACM certificate ARN."
  }
}
variable "site_url" {
  type        = string
  default     = "https://example.invalid"
  description = "Future HTTPS frontend site. Reserved placeholder until configured."
  validation {
    condition     = startswith(var.site_url, "https://")
    error_message = "Production SITE_URL must use HTTPS."
  }
}
variable "cors_origins" {
  type        = string
  default     = "https://example.invalid"
  description = "Exact HTTPS frontend origins; reserved placeholder permits no real frontend by default."
}
variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}
variable "deploy_enabled" {
  type        = bool
  default     = false
  description = "Initial bootstrap false: service has zero tasks. Enable after the first successful pipeline deploy."
}
variable "min_tasks" {
  type    = number
  default = 1
  validation {
    condition     = var.min_tasks >= 1 && var.min_tasks <= 4
    error_message = "Use 1..4 tasks for this micro RDS sizing."
  }
}
variable "max_tasks" {
  type    = number
  default = 1
  validation {
    condition     = var.max_tasks >= var.min_tasks && var.max_tasks <= 4
    error_message = "max_tasks must be >= min_tasks and <=4; resize RDS/pools before increasing."
  }
}
variable "rds_multi_az" {
  type        = bool
  default     = false
  description = "Single-AZ saves cost; true provides database failover at higher cost."
}
variable "postgres_version" {
  type        = string
  default     = "17.6"
  description = "Supported RDS PostgreSQL 17 minor; confirm availability in the selected region before apply."
}
variable "smtp_host" {
  type    = string
  default = "smtp-relay.brevo.com"
}
variable "smtp_from" {
  type        = string
  description = "Verified sender, e.g. Broto <mail@example.com>."
}
variable "google_enabled" {
  type    = bool
  default = false
}
variable "google_client_id" {
  type    = string
  default = ""
}
variable "google_return_urls" {
  type    = string
  default = "broto://auth-callback"
}
variable "anthropic_model" {
  type    = string
  default = "claude-opus-5"
}
variable "chat_model" {
  type    = string
  default = "claude-opus-5"
}
variable "anthropic_effort" {
  type    = string
  default = "medium"
}
variable "initial_image_tag" {
  type        = string
  default     = "bootstrap"
  description = "Placeholder only; deploy_enabled=false avoids pulling it before the pipeline pushes a real image."
}
variable "alarm_email" {
  type        = string
  default     = ""
  description = "Optional operational alarm recipient; SNS email confirmation is required."
}
variable "backup_retention_days" {
  type        = number
  default     = 1
  description = "Free-plan-compatible initial retention; use 7+ after account plan permits. Never disable automated backups."
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be 1..35 days."
  }
}
