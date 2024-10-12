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

resource "aws_api_gateway_method_settings" "auth" {
  rest_api_id = aws_api_gateway_rest_api.auth.id
  stage_name  = aws_api_gateway_deployment.auth.stage_name
  method_path = "*/*" # Apply settings to all methods and resources

  settings {
    logging_level      = "INFO"
    metrics_enabled    = true
    data_trace_enabled = true
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

resource "aws_iam_role" "api_gateway" {
  name               = "${local.resource_name_prefix}-api-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json
}

data "aws_iam_policy_document" "api_gateway" {
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

resource "aws_iam_role_policy" "api_gateway" {
  name   = "${local.resource_name_prefix}-api-gateway-policy"
  role   = aws_iam_role.api_gateway.id
  policy = data.aws_iam_policy_document.api_gateway.json
}

resource "aws_api_gateway_integration" "twitch_callback" {
  rest_api_id             = aws_api_gateway_rest_api.auth.id
  resource_id             = aws_api_gateway_resource.twitch_callback.id
  http_method             = aws_api_gateway_method.twitch_callback.http_method
  credentials             = aws_iam_role.api_gateway.arn
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
}

resource "aws_api_gateway_integration_response" "twitch_callback" {
  rest_api_id = aws_api_gateway_rest_api.auth.id
  resource_id = aws_api_gateway_resource.twitch_callback.id
  http_method = aws_api_gateway_method.twitch_callback.http_method
  status_code = "301"

  response_parameters = {
    "method.response.header.Location" = "'${var.twitch_auth_redirect}'"
  }

  response_templates = {
    "application/json" = "" # No body content needed for redirect
  }

  selection_pattern = ""
}

resource "aws_api_gateway_deployment" "auth" {
  depends_on = [
    aws_api_gateway_integration.twitch_callback,
    aws_api_gateway_integration_response.twitch_callback,
  ]

  rest_api_id = aws_api_gateway_rest_api.auth.id
  stage_name  = var.environment

  lifecycle {
    create_before_destroy = true
  }
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
