resource "terraform_data" "builder_lambda_get_user_subs" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_get_user_subs/"
    command     = "npm install && npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_get_user_subs/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_get_user_subs/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_get_user_subs/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_get_user_subs/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_get_user_subs" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_get_user_subs/dist/"
  output_path = "${path.module}/lambda_get_user_subs/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_get_user_subs
  ]
}

resource "aws_lambda_function" "get_user_subs" {
  function_name    = "${local.resource_name_prefix}-lambda-get-user-subs"
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda_get_user_subs.arn
  filename         = data.archive_file.archiver_lambda_get_user_subs.output_path
  source_code_hash = data.archive_file.archiver_lambda_get_user_subs.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TWITCH_CLIENT_ID     = local.twitch_client_id
      TWITCH_CLIENT_SECRET = local.twitch_client_secret
      DYNAMODB_TABLE_USERS = data.aws_dynamodb_table.users.name
    }
  }

  depends_on = [
    terraform_data.builder_lambda_get_user_subs,
    data.archive_file.archiver_lambda_get_user_subs,
  ]
}

resource "aws_iam_role" "lambda_get_user_subs" {
  name               = "${local.resource_name_prefix}-lambda-get-user-subs-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_get_user_subs" {
  statement {
    actions = ["dynamodb:Query", "dynamodb:UpdateItem"]
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
}

resource "aws_iam_role_policy" "lambda_get_user_subs" {
  name   = "${local.resource_name_prefix}-lambda-get-user-subs-role-policy"
  role   = aws_iam_role.lambda_get_user_subs.id
  policy = data.aws_iam_policy_document.lambda_get_user_subs.json
}
