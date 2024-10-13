resource "aws_api_gateway_rest_api" "twitch" {
  name                         = "${local.resource_name_prefix}-api-gateway"
  disable_execute_api_endpoint = true

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_method_settings" "twitch" {
  rest_api_id = aws_api_gateway_rest_api.twitch.id
  stage_name  = aws_api_gateway_stage.twitch.stage_name
  method_path = "*/*" # Apply settings to all methods and resources

  settings {
    logging_level      = "INFO"
    metrics_enabled    = true
    data_trace_enabled = true
  }
}

resource "aws_api_gateway_deployment" "twitch" {
  rest_api_id = aws_api_gateway_rest_api.twitch.id

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      filebase64sha256("${path.module}/api_gateway.tf"),
      filebase64sha256("${path.module}/eventsub_endpoint.tf")
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.twitch_callback,
    aws_api_gateway_integration_response.twitch_callback,
  ]
}

resource "aws_api_gateway_stage" "twitch" {
  deployment_id = aws_api_gateway_deployment.twitch.id
  rest_api_id   = aws_api_gateway_rest_api.twitch.id
  stage_name    = var.environment
}

resource "aws_api_gateway_base_path_mapping" "twitch" {
  depends_on = [
    aws_api_gateway_deployment.twitch,
  ]

  api_id      = aws_api_gateway_rest_api.twitch.id
  stage_name  = aws_api_gateway_stage.twitch.stage_name
  domain_name = local.domain_api_name
  base_path   = local.stack
}
