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
  stack = "auth"

  resource_name_prefix = "${local.app}-${local.environment}-${local.stack}"

  twitch_client_id     = var.twitch_client_id
  twitch_client_secret = var.twitch_client_secret
}

provider "aws" {
  region = local.aws_region
}
