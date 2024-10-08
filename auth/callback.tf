resource "aws_lambda_function" "oauth_callback" {
  function_name = "${local.resource_name_prefix}-oauth-callback"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = "callback/dist/index.zip"

  environment {
    variables = {
      TWITCH_CLIENT_ID     = local.twitch_client_id
      TWITCH_CLIENT_SECRET = local.twitch_client_secret
      DYNAMODB_TABLE_NAME  = aws_dynamodb_table.twitch_tokens.name
    }
  }
}

resource "aws_api_gateway_rest_api" "oauth_api" {
  name = "${local.resource_name_prefix}-oauth-api"
}

resource "aws_api_gateway_resource" "oauth_resource" {
  rest_api_id = aws_api_gateway_rest_api.oauth_api.id
  parent_id   = aws_api_gateway_rest_api.oauth_api.root_resource_id
  path_part   = "oauth2"
}

resource "aws_api_gateway_method" "oauth_method" {
  rest_api_id   = aws_api_gateway_rest_api.oauth_api.id
  resource_id   = aws_api_gateway_resource.oauth_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "oauth_integration" {
  rest_api_id             = aws_api_gateway_rest_api.oauth_api.id
  resource_id             = aws_api_gateway_resource.oauth_resource.id
  http_method             = aws_api_gateway_method.oauth_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.oauth_callback.invoke_arn
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.oauth_callback.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.oauth_api.execution_arn}/*/*"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${local.resource_name_prefix}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy_attachment" "lambda_basic_execution" {
  name       = "${local.resource_name_prefix}-lambda-basic-execution"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}