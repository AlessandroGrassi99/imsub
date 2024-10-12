resource "terraform_data" "builder_lambda_twitch_callback" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_callback/"
    command = "npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_callback/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_callback/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_callback/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_callback/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_twitch_callback" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_callback/dist/"
  output_path = "${path.module}/lambda_callback/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_twitch_callback
  ]
}

resource "aws_lambda_function" "twitch_callback" {
  function_name    = "${local.resource_name_prefix}-lambda-twitch-callback"
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda_twitch_callback.arn
  filename         = data.archive_file.archiver_lambda_twitch_callback.output_path
  source_code_hash = data.archive_file.archiver_lambda_twitch_callback.output_base64sha256

  environment {
    variables = {
      TWITCH_CLIENT_ID      = local.twitch_client_id
      TWITCH_CLIENT_SECRET  = local.twitch_client_secret
      TWITCH_REDIRECT_URL   = "https://${local.domain_api_name}/auth/callback"
      DYNAMODB_TABLE_USERS  = data.aws_dynamodb_table.users.name
    }
  }

  depends_on = [
    terraform_data.builder_lambda_twitch_callback,
    data.archive_file.archiver_lambda_twitch_callback
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

resource "aws_iam_role" "lambda_twitch_callback" {
  name               = "${local.resource_name_prefix}-lambda-twitch-callback-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_twitch_callback" {
  statement {
    actions = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Query"]
    resources = [
      data.aws_dynamodb_table.users.arn,
      "${data.aws_dynamodb_table.users.arn}/index/*"
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

  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.twitch_callback.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "lambda_twitch_callback" {
  name   = "${local.resource_name_prefix}-lambda-twitch-callback-role-policy"
  role   = aws_iam_role.lambda_twitch_callback.id
  policy = data.aws_iam_policy_document.lambda_twitch_callback.json
}
