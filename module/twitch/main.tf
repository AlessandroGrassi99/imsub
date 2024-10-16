terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "5.72.0" }
  }
}

locals {
  environment = var.environment
  aws_profile = var.aws_profile
  aws_region  = "eu-west-1"

  app   = "imsub"
  stack = "twitch"

  resource_name_prefix = "${local.app}-${local.environment}-${local.stack}"

  domain_api_name      = var.domain_api_name
  twitch_client_id     = var.twitch_client_id
  twitch_client_secret = var.twitch_client_secret
  dynamodb_table_users = var.dynamodb_table_users
}

provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile
}

data "aws_dynamodb_table" "users" {
  name = local.dynamodb_table_users
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}