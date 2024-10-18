resource "terraform_data" "builder_lambda_send_user_auth_link" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_send_user_auth_link/"
    command     = "npm install && npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_send_user_auth_link/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_send_user_auth_link/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_send_user_auth_link/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_send_user_auth_link/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_send_user_auth_link" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_send_user_auth_link/dist/"
  output_path = "${path.module}/lambda_send_user_auth_link/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_send_user_auth_link
  ]
}

resource "aws_lambda_function" "send_user_auth_link" {
  function_name = "${local.resource_name_prefix}-lambda-send-user-auth-link"

  handler = "index.handler"
  runtime = "nodejs20.x"
  publish = true
  role    = aws_iam_role.lambda_send_user_auth_link.arn

  filename         = data.archive_file.archiver_lambda_send_user_auth_link.output_path
  source_code_hash = data.archive_file.archiver_lambda_send_user_auth_link.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TELEGRAM_BOT_TOKEN      = local.telegram_bot_token
      TWITCH_CLIENT_ID        = local.twitch_client_id
      TWITCH_REDIRECT_URL     = "https://${local.twitch_redirect_url}"
      DYNAMODB_TABLE_AUTH_STATES = data.aws_dynamodb_table.auth_states.name
      STATE_TTL_SECONDS       = 7200 # 2 Hour
    }
  }

  depends_on = [
    terraform_data.builder_lambda_send_user_auth_link,
    data.archive_file.archiver_lambda_send_user_auth_link
  ]
}

resource "aws_iam_role" "lambda_send_user_auth_link" {
  name               = "${local.resource_name_prefix}-lambda-send-user-auth-link-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_send_user_auth_link" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
    effect    = "Allow"
  }

  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [data.aws_dynamodb_table.auth_states.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "lambda_send_user_auth_link" {
  name   = "${local.resource_name_prefix}-lambda-send-user-auth-link-role-policy"
  role   = aws_iam_role.lambda_send_user_auth_link.id
  policy = data.aws_iam_policy_document.lambda_send_user_auth_link.json
}
