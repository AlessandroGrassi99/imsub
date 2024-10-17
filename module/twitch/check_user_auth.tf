resource "terraform_data" "builder_lambda_check_user_auth" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_check_user_auth/"
    command     = "npm install && npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_check_user_auth/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_check_user_auth/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_check_user_auth/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_check_user_auth/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_check_user_auth" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_check_user_auth/dist/"
  output_path = "${path.module}/lambda_check_user_auth/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_check_user_auth
  ]
}

resource "aws_lambda_function" "check_user_auth" {
  function_name    = "${local.resource_name_prefix}-lambda-check-user-auth"
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda_check_user_auth.arn
  filename         = data.archive_file.archiver_lambda_check_user_auth.output_path
  source_code_hash = data.archive_file.archiver_lambda_check_user_auth.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TWITCH_CLIENT_ID     = local.twitch_client_id
      TWITCH_CLIENT_SECRET = local.twitch_client_secret
      DYNAMODB_TABLE_USERS = data.aws_dynamodb_table.users.name
    }
  }

  depends_on = [
    terraform_data.builder_lambda_check_user_auth,
    data.archive_file.archiver_lambda_check_user_auth,
  ]
}

resource "aws_iam_role" "lambda_check_user_auth" {
  name               = "${local.resource_name_prefix}-lambda-check-user-auth-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_check_user_auth" {
  statement {
    actions = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
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

resource "aws_iam_role_policy" "lambda_check_user_auth" {
  name   = "${local.resource_name_prefix}-lambda-check-user-auth-role-policy"
  role   = aws_iam_role.lambda_check_user_auth.id
  policy = data.aws_iam_policy_document.lambda_check_user_auth.json
}
