resource "aws_api_gateway_rest_api" "auth" {
  name = "${local.resource_name_prefix}-api-gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "twitch_callback" {
  rest_api_id = aws_api_gateway_rest_api.auth.id
  parent_id   = aws_api_gateway_rest_api.auth.root_resource_id
  path_part   = "callback"
}

resource "aws_api_gateway_method" "twitch_callback" {
  rest_api_id   = aws_api_gateway_rest_api.auth.id
  resource_id   = aws_api_gateway_resource.twitch_callback.id
  http_method   = "GET"
  authorization = "NONE"
}

## Set API Gateway role

data "aws_iam_policy_document" "api_gateway_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_gateway_twitch_callback" {
  name               = "${local.resource_name_prefix}-api-gateway-twitch-callback-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json
}

data "aws_iam_policy_document" "api_gateway_twitch_callback" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.twitch_callback.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "api_gateway_twitch_callback" {
  name   = "${local.resource_name_prefix}-api-gateway-twitch-callback-role-policy"
  role   = aws_iam_role.api_gateway_twitch_callback.id
  policy = data.aws_iam_policy_document.api_gateway_twitch_callback.json
}

resource "aws_api_gateway_integration" "twitch_callback" {
  rest_api_id             = aws_api_gateway_rest_api.auth.id
  resource_id             = aws_api_gateway_resource.twitch_callback.id
  http_method             = aws_api_gateway_method.twitch_callback.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.twitch_callback.invoke_arn
  credentials             = aws_iam_role.api_gateway_twitch_callback.arn
}

resource "aws_lambda_permission" "twitch_callback" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.twitch_callback.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.auth.execution_arn}/*/POST/callback"
}

resource "aws_api_gateway_deployment" "auth" {
  depends_on = [
    aws_api_gateway_integration.twitch_callback
  ]

  rest_api_id = aws_api_gateway_rest_api.auth.id
  stage_name  = var.environment
}

resource "aws_api_gateway_base_path_mapping" "auth" {
  depends_on = [
    aws_api_gateway_deployment.auth,
  ]

  api_id      = aws_api_gateway_rest_api.auth.id
  stage_name  = aws_api_gateway_deployment.auth.stage_name
  domain_name = local.domain_api_name
  base_path   = "auth"
}
