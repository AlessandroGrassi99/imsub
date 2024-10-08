terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "5.70.0" }
  }

  backend "s3" {
    region = "eu-west-1"
  }
}

locals {
  environment = var.environment
  aws_region  = "eu-west-1"
  aws_profile = var.aws_profile

  app   = "imsub"
  stack = "telegram"

  resource_name_prefix = "${local.app}-${local.environment}-${local.stack}"

  telegram_bot_token     = var.telegram_bot_token
  twitch_redirect_url    = var.twitch_redirect_url
  twitch_client_id       = var.twitch_client_id
  domain_api             = var.domain_api
  domain_api_certificate = var.domain_api_certificate
}

provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile
}
