resource "terraform_data" "build_lambda_twitch_callback" {
  provisioner "local-exec" {
    command = <<EOT
      cd ${path.module}/callback/;
      echo 'Cleaning ${local.resource_name_prefix}-lambda-twitch-callback'
      npm run clean
      echo 'Building ${local.resource_name_prefix}-lambda-twitch-callback'
      npm run build
      echo 'Built ${local.resource_name_prefix}-lambda-twitch-callback'
    EOT
  }

  triggers_replace = [
    filemd5("${path.module}/callback/index.ts"),
  ]
}

resource "aws_lambda_function" "twitch_callback" {
  function_name    = "${local.resource_name_prefix}-lambda-twitch-callback"
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda_twitch_callback.arn
  filename         = "${path.module}/callback/dist/index.zip"
  source_code_hash = filemd5("${path.module}/callback/dist/index.zip")

  environment {
    variables = {
      TWITCH_CLIENT_ID      = local.twitch_client_id
      TWITCH_CLIENT_SECRET  = local.twitch_client_secret
      TWITCH_REDIRECT_URL   = "https://${local.domain_api_name}/auth/callback"
      DYNAMODB_TABLE_STATES = data.aws_dynamodb_table.auth_states.name
      DYNAMODB_TABLE_USERS  = data.aws_dynamodb_table.users.name
    }
  }
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

resource "aws_iam_role" "lambda_twitch_callback" {
  name               = "${local.resource_name_prefix}-lambda-twitch-callback-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_twitch_callback" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:DeleteItem"]
    resources = [data.aws_dynamodb_table.auth_states.arn]
    effect    = "Allow"
  }

  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [data.aws_dynamodb_table.users.arn]
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

  # statement {
  #   actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
  #   resources = [aws_dynamodb_table.twitch_tokens.arn]
  #   effect   = "Allow"
  # }
}

resource "aws_iam_role_policy" "lambda_twitch_callback" {
  name   = "${local.resource_name_prefix}-lambda-twitch-callback-role-policy"
  role   = aws_iam_role.lambda_twitch_callback.id
  policy = data.aws_iam_policy_document.lambda_twitch_callback.json
}
