terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "5.70.0" }
  }

  backend "s3" {
    region = "eu-west-1"
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be one of: dev, prod."
  }
}

variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
}

variable "namecheap_username" {
  type      = string
  sensitive = true
}

variable "namecheap_api_key" {
  type      = string
  sensitive = true
}

variable "domain" {
  type = string
}

variable "telegram_bot_token" {
  type      = string
  sensitive = true
}

variable "twitch_client_id" {
  type = string
}

variable "twitch_client_secret" {
  type      = string
  sensitive = true
}

module "common" {
  source = "./common"

  environment = var.environment
  aws_profile = var.aws_profile
}

module "web" {
  source = "./web"

  environment        = var.environment
  aws_profile        = var.aws_profile
  namecheap_username = var.namecheap_username
  namecheap_api_key  = var.namecheap_api_key
  domain             = var.domain
}

module "telegram" {
  source = "./telegram"

  environment               = var.environment
  aws_profile               = var.aws_profile
  twitch_redirect_url       = "api.${var.domain}/auth/callback" # TODO: Get from auth
  twitch_client_id          = var.twitch_client_id
  telegram_bot_token        = var.telegram_bot_token
  domain_api_name           = module.web.domain_api_name
  dynamodb_table_auth_states = module.common.dynamodb_table_auth_states
}

module "auth" {
  source = "./auth"

  environment          = var.environment
  aws_profile          = var.aws_profile
  twitch_client_id     = var.twitch_client_id
  twitch_client_secret = var.twitch_client_secret
  domain_api_name           = module.web.domain_api_name
  dynamodb_table_auth_states = module.common.dynamodb_table_auth_states
  dynamodb_table_users = module.common.dynamodb_table_users
}