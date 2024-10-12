terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "5.71.0" }
    null   = { source = "hashicorp/null", version = "3.2.3" }
    random = { source = "hashicorp/random", version = "3.6.3" }
  }
}

locals {
  environment = var.environment
  aws_region  = "eu-west-1"
  aws_profile = var.aws_profile

  app   = "imsub"
  stack = "telegram"

  resource_name_prefix = "${local.app}-${local.environment}-${local.stack}"

  telegram_bot_token         = var.telegram_bot_token
  twitch_redirect_url        = var.twitch_redirect_url
  twitch_client_id           = var.twitch_client_id
  domain_api_name            = var.domain_api_name
  dynamodb_table_auth_states = var.dynamodb_table_auth_states
}

provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile
}

resource "random_password" "telegram_webhook_secret" {
  length  = 32
  special = false
}

resource "terraform_data" "telegram_set_webhook" {
  provisioner "local-exec" {
    command = <<EOT
      curl -s -F "url=https://${local.domain_api_name}/telegram/webhook" \
      -F "secret_token=${random_password.telegram_webhook_secret.result}" \
      https://api.telegram.org/bot${var.telegram_bot_token}/setWebhook
    EOT
  }
}

data "aws_dynamodb_table" "auth_states" {
  name = local.dynamodb_table_auth_states
}