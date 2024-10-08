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

  role = aws_iam_role.lambda_webhook.arn

  filename         = "${path.module}/webhook/dist/index.zip"
  source_code_hash = filemd5("${path.module}/webhook/dist/index.zip")
  timeout          = 120
  environment {
    variables = {
      TELEGRAM_BOT_TOKEN  = local.telegram_bot_token
      TWITCH_CLIENT_ID    = local.twitch_client_id
      TWITCH_REDIRECT_URL = local.twitch_redirect_url
    }
  }

  depends_on = [terraform_data.build_lambda_webhook]
}

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
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}
