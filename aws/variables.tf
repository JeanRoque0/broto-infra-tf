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
  description = "Future DNS name, e.g. api.example.com."
}
variable "route53_zone_id" {
  type        = string
  description = "ID of the future public Route53 zone for DNS and ACM validation."
}
variable "site_url" {
  type        = string
  description = "HTTPS URL of the frontend site."
  validation {
    condition     = startswith(var.site_url, "https://")
    error_message = "Production SITE_URL must use HTTPS."
  }
}
variable "cors_origins" {
  type        = string
  description = "Comma-separated exact HTTPS frontend origins."
}
variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}
variable "private_compute" {
  type        = bool
  default     = false
  description = "false: public-IP hosts, bridge tasks, no inbound Internet access. true: private hosts and one NAT Gateway (extra fixed cost, single-AZ egress)."
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
  default = 4
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
