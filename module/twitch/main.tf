terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "5.71.0" }
  }
}

locals {
  environment = var.environment
  aws_profile = var.aws_profile
  aws_region  = "eu-west-1"

  app   = "imsub"
  stack = "twitch"

  resource_name_prefix = "${local.app}-${local.environment}-${local.stack}"

  twitch_client_id     = var.twitch_client_id
  twitch_client_secret = var.twitch_client_secret
  twitch_redirect_url  = var.twitch_redirect_url
  dynamodb_table_users = var.dynamodb_table_users
}

provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile
}

data "aws_dynamodb_table" "users" {
  name = local.dynamodb_table_users
}