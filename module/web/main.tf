terraform {
  required_version = ">= 1.9"
  required_providers {
    aws       = { source = "hashicorp/aws", version = "5.70.0" }
    namecheap = { source = "namecheap/namecheap", version = "2.1.2" }
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
  stack = "web"

  resource_name_prefix = "${local.app}-${local.environment}-${local.stack}"

  namecheap_username = var.namecheap_username
  namecheap_api_user = var.namecheap_username
  namecheap_api_key  = var.namecheap_api_key

  domain = var.domain
}

provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = local.aws_profile
}

provider "namecheap" {
  user_name = local.namecheap_username
  api_user  = local.namecheap_api_user
  api_key   = local.namecheap_api_key
}

# Route53 Zone
resource "aws_route53_zone" "main" {
  name = local.domain
}

# Update Namecheap Nameservers to Route53
resource "namecheap_domain_records" "domain_ns" {
  domain      = local.domain
  mode        = "OVERWRITE"
  nameservers = aws_route53_zone.main.name_servers
}

resource "aws_acm_certificate" "api" {
  domain_name       = "api.${local.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

output "domain_api_certificate" {
  value = aws_acm_certificate.api.arn
}

output "domain_zone_id" {
  value = aws_route53_zone.main.zone_id
}
