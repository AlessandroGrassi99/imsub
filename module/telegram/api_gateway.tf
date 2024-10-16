resource "aws_api_gateway_rest_api" "telegram" {
  name                         = "${local.resource_name_prefix}-api-gateway"
  disable_execute_api_endpoint = true

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_method_settings" "telegram" {
  rest_api_id = aws_api_gateway_rest_api.telegram.id
  stage_name  = aws_api_gateway_stage.telegram.stage_name
  method_path = "*/*" # Apply settings to all methods and resources

  settings {
    logging_level      = "INFO"
    metrics_enabled    = true
    data_trace_enabled = true
  }
}

resource "aws_api_gateway_deployment" "telegram" {
  rest_api_id = aws_api_gateway_rest_api.telegram.id

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      filebase64sha256("${path.module}/webhook_endpoint.tf"),
      filebase64sha256("${path.module}/api_gateway.tf"),
      data.archive_file.archiver_lambda_webhook.output_base64sha256,
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.telegram_webhook,
  ]
}

resource "aws_api_gateway_stage" "telegram" {
  deployment_id = aws_api_gateway_deployment.telegram.id
  rest_api_id   = aws_api_gateway_rest_api.telegram.id
  stage_name    = var.environment
}

resource "aws_api_gateway_base_path_mapping" "telegram" {
  depends_on = [
    aws_api_gateway_deployment.telegram,
  ]

  api_id      = aws_api_gateway_rest_api.telegram.id
  stage_name  = aws_api_gateway_stage.telegram.stage_name
  domain_name = local.domain_api_name
  base_path   = "telegram"
}

data "aws_iam_policy_document" "api_gateway_telegram" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.telegram.execution_arn}/*"]
  }

  statement {
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.telegram.execution_arn}/*"]

    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      # Ref: https://core.telegram.org/bots/webhooks
      values = [
        "149.154.160.0/20",
        "91.108.4.0/22"
      ]
    }
  }
}

resource "aws_api_gateway_rest_api_policy" "api_gateway_telegram" {
  rest_api_id = aws_api_gateway_rest_api.telegram.id
  policy      = data.aws_iam_policy_document.api_gateway_telegram.json
}

# resource "aws_wafv2_ip_set" "allowed_ips" {
#   name               = "AllowedIPs"
#   description        = "IP set for allowed source IPs."
#   scope              = "REGIONAL"
#   ip_address_version = "IPV4"

#   addresses = [
#     "149.154.160.0/20",
#     "91.108.4.0/22"
#   ]
# }