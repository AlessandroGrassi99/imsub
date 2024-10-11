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
Action=SendMessage&MessageBody=
#set($allParams = $input.params())
{
"body-json" : $input.json('$'),
"params" : {
#foreach($type in $allParams.keySet())
    #set($params = $allParams.get($type))
"$type" : {
    #foreach($paramName in $params.keySet())
    "$paramName" : "$util.escapeJavaScript($params.get($paramName))"
        #if($foreach.hasNext),#end
    #end
}
    #if($foreach.hasNext),#end
#end
},
"stage-variables" : {
#foreach($key in $stageVariables.keySet())
"$key" : "$util.escapeJavaScript($stageVariables.get($key))"
    #if($foreach.hasNext),#end
#end
},
"context" : {
    "account-id" : "$context.identity.accountId",
    "api-id" : "$context.apiId",
    "api-key" : "$context.identity.apiKey",
    "authorizer-principal-id" : "$context.authorizer.principalId",
    "caller" : "$context.identity.caller",
    "cognito-authentication-provider" : "$context.identity.cognitoAuthenticationProvider",
    "cognito-authentication-type" : "$context.identity.cognitoAuthenticationType",
    "cognito-identity-id" : "$context.identity.cognitoIdentityId",
    "cognito-identity-pool-id" : "$context.identity.cognitoIdentityPoolId",
    "http-method" : "$context.httpMethod",
    "stage" : "$context.stage",
    "source-ip" : "$context.identity.sourceIp",
    "user" : "$context.identity.user",
    "user-agent" : "$context.identity.userAgent",
    "user-arn" : "$context.identity.userArn",
    "request-id" : "$context.requestId",
    "resource-id" : "$context.resourceId",
    "resource-path" : "$context.resourcePath"
    }
}
EOF
  }
  passthrough_behavior = "NEVER"
}


# Define the default method response
resource "aws_api_gateway_method_response" "twitch_callback" {
  rest_api_id = aws_api_gateway_rest_api.auth.id
  resource_id = aws_api_gateway_resource.twitch_callback.id
  http_method = aws_api_gateway_method.twitch_callback.http_method
  status_code = "301"

  response_parameters = {
    "method.response.header.Location" = true
  }
}

# Define the integration response
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
    aws_api_gateway_integration_response.twitch_callback,
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
