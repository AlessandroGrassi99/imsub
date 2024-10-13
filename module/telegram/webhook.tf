resource "terraform_data" "builder_lambda_webhook" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_webhook/"
    command     = "npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_webhook/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_webhook/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_webhook/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_webhook/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_webhook" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_webhook/dist/"
  output_path = "${path.module}/lambda_webhook/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_webhook
  ]
}

resource "aws_lambda_function" "webhook" {
  function_name = "${local.resource_name_prefix}-lambda-webhook"

  handler = "index.handler"
  runtime = "nodejs20.x"
  publish = true
  role    = aws_iam_role.lambda_webhook.arn

  filename         = data.archive_file.archiver_lambda_webhook.output_path
  source_code_hash = data.archive_file.archiver_lambda_webhook.output_base64sha256
  timeout          = 120

  environment {
    variables = {
      TELEGRAM_BOT_TOKEN      = local.telegram_bot_token
      TWITCH_CLIENT_ID        = local.twitch_client_id
      TWITCH_REDIRECT_URL     = "https://${local.twitch_redirect_url}"
      TELEGRAM_WEBHOOK_SECRET = random_password.telegram_webhook_secret.result
      DYNAMODB_TABLE_STATES   = data.aws_dynamodb_table.auth_states.name
      STATE_TTL_SECONDS       = 7200 # 2 Hour
    }
  }

  depends_on = [
    terraform_data.builder_lambda_webhook,
    data.archive_file.archiver_lambda_webhook
  ]
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
