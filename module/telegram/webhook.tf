resource "terraform_data" "builder_lambda_webhook" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_webhook/"
    command     = "npm install && npm run build"
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
  timeout          = 20

  environment {
    variables = {
      TELEGRAM_BOT_TOKEN                    = local.telegram_bot_token
      TELEGRAM_WEBHOOK_SECRET               = random_password.telegram_webhook_secret.result
      SQS_SEND_USER_STATUS_URL              = aws_sqs_queue.send_user_status.url
      SQS_CHECK_JOIN_REQUEST_URL            = aws_sqs_queue.check_join_request.url
      UPSTASH_REDIS_DATABASE_CACHE_ENDPOINT = var.upstash_redis_database_cache_endpoint
      UPSTASH_REDIS_DATABASE_CACHE_PASSWORD = var.upstash_redis_database_cache_password
      STATE_TTL_SECONDS                     = 7200 # 2 Hour
    }
  }

  depends_on = [
    terraform_data.builder_lambda_webhook,
    data.archive_file.archiver_lambda_webhook,
  ]
}

resource "aws_lambda_provisioned_concurrency_config" "webhook" {
  function_name                     = aws_lambda_function.webhook.function_name
  provisioned_concurrent_executions = 1
  qualifier                         = aws_lambda_function.webhook.version
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
    actions = ["sqs:SendMessage"]
    resources = [
      aws_sqs_queue.send_user_status.arn,
      aws_sqs_queue.check_join_request.arn
    ]
    effect = "Allow"
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
