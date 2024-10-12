resource "terraform_data" "build_lambda_webhook" {
  provisioner "local-exec" {
    command = <<EOT
      echo 'Cleaning ${local.resource_name_prefix}-lambda-webhook'
      rm -rf ${path.module}/webhook/dist/*
      echo 'Building ${local.resource_name_prefix}-lambda-webhook'
      cd ${path.module}/webhook/; npm run build
      echo 'Built ${local.resource_name_prefix}-lambda-webhook'
    EOT
  }

  triggers_replace = [
    filemd5("${path.module}/webhook/index.ts"),
  ]
}

resource "aws_lambda_function" "webhook" {
  function_name = "${local.resource_name_prefix}-lambda-webhook"

  handler = "index.handler"
  runtime = "nodejs20.x"
  publish = true
  role = aws_iam_role.lambda_webhook.arn

  filename         = "${path.module}/webhook/dist/index.zip"
  source_code_hash = filemd5("${path.module}/webhook/dist/index.zip")
  timeout          = 120
  
  environment {
    variables = {
      TELEGRAM_BOT_TOKEN      = local.telegram_bot_token
      TWITCH_CLIENT_ID        = local.twitch_client_id
      TWITCH_REDIRECT_URL     = "https://${local.twitch_redirect_url}"
      TELEGRAM_WEBHOOK_SECRET = random_password.telegram_webhook_secret.result
      DYNAMODB_TABLE_STATES   = data.aws_dynamodb_table.auth_states.name
    }
  }

  depends_on = [terraform_data.build_lambda_webhook]
}

# resource "aws_lambda_provisioned_concurrency_config" "webhook" {
#   function_name                     = aws_lambda_function.webhook.function_name
#   provisioned_concurrent_executions = 1
#   qualifier                         = aws_lambda_function.webhook.version

#   depends_on = [ aws_lambda_function.webhook ]
# }

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_webhook" {
  name               = "${local.resource_name_prefix}-lambda-webhook-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_webhook" {
  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [data.aws_dynamodb_table.auth_states.arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "lambda_webhook" {
  name   = "${local.resource_name_prefix}-lambda-webhook-role-policy"
  role   = aws_iam_role.lambda_webhook.id
  policy = data.aws_iam_policy_document.lambda_webhook.json
}
