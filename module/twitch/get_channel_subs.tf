resource "terraform_data" "builder_lambda_channel_subs" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_channel_subs/"
    command     = "npm install && npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_channel_subs/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_channel_subs/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_channel_subs/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_channel_subs/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_channel_subs" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_channel_subs/dist/"
  output_path = "${path.module}/lambda_channel_subs/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_channel_subs
  ]
}

resource "aws_lambda_function" "channel_subs" {
  function_name    = "${local.resource_name_prefix}-lambda-channel-subs-check"
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda_channel_subs.arn
  filename         = data.archive_file.archiver_lambda_channel_subs.output_path
  source_code_hash = data.archive_file.archiver_lambda_channel_subs.output_base64sha256
  timeout          = 300

  environment {
    variables = {
      TWITCH_CLIENT_ID     = local.twitch_client_id
      TWITCH_CLIENT_SECRET = local.twitch_client_secret
      # DYNAMODB_TABLE_SUBSCRIPTIONS = aws_dynamodb_table.subscriptions.name
    }
  }

  depends_on = [
    terraform_data.builder_lambda_channel_subs,
    data.archive_file.archiver_lambda_channel_subs,
  ]
}

resource "aws_iam_role" "lambda_channel_subs" {
  name               = "${local.resource_name_prefix}-lambda-channel-subs-check-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_channel_subs" {
  # statement {
  #   actions = ["dynamodb:BatchWriteItem"]
  #   resources = [
  #     aws_dynamodb_table.subscriptions.arn,
  #     "${aws_dynamodb_table.subscriptions.arn}/*"
  #   ]
  #   effect = "Allow"
  # }

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

resource "aws_iam_role_policy" "lambda_channel_subs" {
  name   = "${local.resource_name_prefix}-lambda-channel-subs-check-role-policy"
  role   = aws_iam_role.lambda_channel_subs.id
  policy = data.aws_iam_policy_document.lambda_channel_subs.json
}
