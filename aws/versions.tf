terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {}
}
provider "aws" {
  region = var.aws_region
  default_tags { tags = { Project = var.name, ManagedBy = "Terraform" } }
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_availability_zones" "available" { state = "available" }
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}
locals {
  account     = data.aws_caller_identity.current.account_id
  prefix      = "arn:${data.aws_partition.current.partition}"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  task_cpu    = 2048
  task_memory = 780
  db_pool     = 4
  image       = "${aws_ecr_repository.api.repository_url}:${var.initial_image_tag}"
}
