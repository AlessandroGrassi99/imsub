
resource "aws_api_gateway_rest_api" "webhook" {
  name = "${local.resource_name_prefix}-gateway-webhook"
}

resource "aws_api_gateway_resource" "webhook_res" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  parent_id   = aws_api_gateway_rest_api.webhook.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  resource_id   = aws_api_gateway_resource.webhook_res.id
  http_method   = "POST"
  authorization = "NONE"
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

resource "aws_iam_role" "api_gateway_webhook" {
  name               = "${local.resource_name_prefix}-api-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json
}

data "aws_iam_policy_document" "api_gateway_webhook" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.webhook.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "api_gateway_webhook" {
  name   = "${local.resource_name_prefix}-api-gateway-webhook-role-policy"
  role   = aws_iam_role.api_gateway_webhook.id
  policy = data.aws_iam_policy_document.api_gateway_webhook.json
}


resource "aws_api_gateway_integration" "webhook" {
  rest_api_id             = aws_api_gateway_rest_api.webhook.id
  resource_id             = aws_api_gateway_resource.webhook_res.id
  http_method             = aws_api_gateway_method.webhook.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook.invoke_arn
  credentials             = aws_iam_role.api_gateway_webhook.arn
}

resource "aws_lambda_permission" "webhook" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.webhook.execution_arn}/*/POST/webhook"
}

resource "aws_api_gateway_deployment" "webhook" {
  depends_on = [
    aws_api_gateway_integration.webhook
  ]

  rest_api_id = aws_api_gateway_rest_api.webhook.id
  stage_name  = var.environment
}