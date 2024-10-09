resource "aws_api_gateway_rest_api" "telegram" {
  name = "${local.resource_name_prefix}-api-gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "telegram_webhook" {
  rest_api_id = aws_api_gateway_rest_api.telegram.id
  parent_id   = aws_api_gateway_rest_api.telegram.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "telegram_webhook" {
  rest_api_id   = aws_api_gateway_rest_api.telegram.id
  resource_id   = aws_api_gateway_resource.telegram_webhook.id
  http_method   = "POST"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.X-Telegram-Bot-Api-Secret-Token" = true
  }
}

data "aws_iam_policy_document" "api_gateway_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_gateway_telegram_webhook" {
  name               = "${local.resource_name_prefix}-api-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json
}

data "aws_iam_policy_document" "api_gateway_telegram" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.webhook.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "api_gateway_webhook" {
  name   = "${local.resource_name_prefix}-api-gateway-role-policy"
  role   = aws_iam_role.api_gateway_telegram_webhook.id
  policy = data.aws_iam_policy_document.api_gateway_telegram.json
}

resource "aws_api_gateway_integration" "telegram_webhook" {
  rest_api_id             = aws_api_gateway_rest_api.telegram.id
  resource_id             = aws_api_gateway_resource.telegram_webhook.id
  http_method             = aws_api_gateway_method.telegram_webhook.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook.invoke_arn
  credentials             = aws_iam_role.api_gateway_telegram_webhook.arn
}

resource "aws_lambda_permission" "webhook" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.telegram.execution_arn}/*/POST/webhook"
}

resource "aws_api_gateway_deployment" "telegram" {
  depends_on = [
    aws_api_gateway_integration.telegram_webhook,
    # aws_api_gateway_integration.telegram_webhook_options
  ]

  rest_api_id = aws_api_gateway_rest_api.telegram.id
  stage_name  = var.environment
}

resource "aws_api_gateway_base_path_mapping" "telegram" {
  depends_on = [
    aws_api_gateway_deployment.telegram,
  ]

  api_id      = aws_api_gateway_rest_api.telegram.id
  stage_name  = aws_api_gateway_deployment.telegram.stage_name
  domain_name = local.domain_api_name
  base_path   = "telegram"
}
