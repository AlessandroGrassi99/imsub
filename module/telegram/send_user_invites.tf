resource "terraform_data" "builder_lambda_send_user_invites" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_send_user_invites/"
    command     = "npm install && npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_send_user_invites/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_send_user_invites/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_send_user_invites/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_send_user_invites/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_send_user_invites" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_send_user_invites/dist/"
  output_path = "${path.module}/lambda_send_user_invites/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_send_user_invites
  ]
}

resource "aws_lambda_function" "send_user_invites" {
  function_name = "${local.resource_name_prefix}-lambda-send-user-invites"

  handler = "index.handler"
  runtime = "nodejs20.x"
  publish = true
  role    = aws_iam_role.lambda_send_user_invites.arn

  filename         = data.archive_file.archiver_lambda_send_user_invites.output_path
  source_code_hash = data.archive_file.archiver_lambda_send_user_invites.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TELEGRAM_BOT_TOKEN      = local.telegram_bot_token
      DYNAMODB_TABLE_CREATORS = data.aws_dynamodb_table.creators.name
      TWITCH_CLIENT_ID        = local.twitch_client_id
      TWITCH_REDIRECT_URL     = "https://${local.twitch_redirect_url}"
      TELEGRAM_WEBHOOK_SECRET = random_password.telegram_webhook_secret.result
      DYNAMODB_TABLE_STATES   = data.aws_dynamodb_table.auth_states.name
    }
  }

  depends_on = [
    terraform_data.builder_lambda_send_user_invites,
    data.archive_file.archiver_lambda_send_user_invites
  ]
}

resource "aws_iam_role" "lambda_send_user_invites" {
  name               = "${local.resource_name_prefix}-lambda-send-user-invites-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_send_user_invites" {
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
    actions   = ["dynamodb:Query"]
    resources = ["${data.aws_dynamodb_table.creators.arn}/index/twitch_id_index"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "lambda_send_user_invites" {
  name   = "${local.resource_name_prefix}-lambda-send-user-invites-role-policy"
  role   = aws_iam_role.lambda_send_user_invites.id
  policy = data.aws_iam_policy_document.lambda_send_user_invites.json
}
