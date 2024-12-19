terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "5.82.1" }
    upstash = { source = "upstash/upstash", version = "1.5.3" }
  }
}

locals {
  environment = var.environment
  aws_region  = "eu-west-1"
  aws_profile = var.aws_profile

  app   = "imsub"
  stack = "common"

  resource_name_prefix = "${local.app}-${local.environment}-${local.stack}"
}

provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile
}

provider "upstash" {
  email   = var.upstash_email
  api_key = var.upstash_api_key
}
