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

resource "aws_api_gateway_integration" "twitch_callback" {
  rest_api_id             = aws_api_gateway_rest_api.auth.id
  resource_id             = aws_api_gateway_resource.twitch_callback.id
  http_method             = aws_api_gateway_method.twitch_callback.http_method
  credentials             = aws_iam_role.api_gateway_integration_request_twitch_callback.arn
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.twitch_callback.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = <<EOF
Action=SendMessage&MessageBody={
  "code": "$util.escapeJavaScript($input.params('code'))",
  "scope": "$util.escapeJavaScript($util.urlDecode($input.params('scope')))",
  "state": "$util.escapeJavaScript($input.params('state'))"
}
EOF
  }
  passthrough_behavior = "NEVER"
}

resource "aws_api_gateway_method_response" "twitch_callback" {
  rest_api_id = aws_api_gateway_rest_api.auth.id
  resource_id = aws_api_gateway_resource.twitch_callback.id
  http_method = aws_api_gateway_method.twitch_callback.http_method
  status_code = "301"

  response_parameters = {
    "method.response.header.Location" = true
  }

  depends_on = [ 
    aws_api_gateway_integration.twitch_callback 
  ]
}

resource "aws_api_gateway_integration_response" "twitch_callback" {
  rest_api_id = aws_api_gateway_rest_api.auth.id
  resource_id = aws_api_gateway_resource.twitch_callback.id
  http_method = aws_api_gateway_method_response.twitch_callback.http_method
  status_code = "301"

  response_parameters = {
    "method.response.header.Location" = "'${var.twitch_auth_redirect}'"
  }

  response_templates = {
    "application/json" = "" # No body content needed for redirect
  }

  selection_pattern = ""

  depends_on = [ 
    aws_api_gateway_integration.twitch_callback
  ]
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

resource "aws_iam_role" "api_gateway_integration_request_twitch_callback" {
  name               = "${local.resource_name_prefix}-api-gateway-integration-twitch-callback-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json
}

data "aws_iam_policy_document" "api_gateway_integration_request_twitch_callback" {
  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [aws_sqs_queue.twitch_callback.arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "api_gateway_integration_request_twitch_callback" {
  name   = "${local.resource_name_prefix}-api-gateway-integration-twitch-callback-role-policy"
  role   = aws_iam_role.api_gateway_integration_request_twitch_callback.id
  policy = data.aws_iam_policy_document.api_gateway_integration_request_twitch_callback.json
}