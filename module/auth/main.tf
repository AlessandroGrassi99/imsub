terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "5.71.0" }
  }
}

locals {
  environment = var.environment
  aws_region  = "eu-west-1"
  aws_profile = var.aws_profile

  app   = "imsub"
  stack = "auth"

  resource_name_prefix = "${local.app}-${local.environment}-${local.stack}"

  twitch_client_id           = var.twitch_client_id
  twitch_client_secret       = var.twitch_client_secret
  dynamodb_table_auth_states = var.dynamodb_table_auth_states
  dynamodb_table_users       = var.dynamodb_table_users
  domain_api_name            = var.domain_api_name
}

provider "aws" {
  region = local.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_dynamodb_table" "auth_states" {
  name = local.dynamodb_table_auth_states
}

data "aws_dynamodb_table" "users" {
  name = local.dynamodb_table_users
}