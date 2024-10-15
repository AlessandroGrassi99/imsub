resource "terraform_data" "builder_lambda_auth_check" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_auth_check/"
    command     = "npm install && npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_auth_check/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_auth_check/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_auth_check/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_auth_check/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_auth_check" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_auth_check/dist/"
  output_path = "${path.module}/lambda_auth_check/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_auth_check
  ]
}

resource "aws_lambda_function" "auth_check" {
  function_name    = "${local.resource_name_prefix}-lambda-auth-check"
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda_auth_check.arn
  filename         = data.archive_file.archiver_lambda_auth_check.output_path
  source_code_hash = data.archive_file.archiver_lambda_auth_check.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TWITCH_CLIENT_ID     = local.twitch_client_id
      TWITCH_CLIENT_SECRET = local.twitch_client_secret
      DYNAMODB_TABLE_USERS = data.aws_dynamodb_table.users.name
    }
  }

  depends_on = [
    terraform_data.builder_lambda_auth_check,
    data.archive_file.archiver_lambda_auth_check,
  ]
}

resource "aws_iam_role" "lambda_auth_check" {
  name               = "${local.resource_name_prefix}-lambda-auth-check-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_auth_check" {
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

resource "aws_iam_role_policy" "lambda_auth_check" {
  name   = "${local.resource_name_prefix}-lambda-auth-check-role-policy"
  role   = aws_iam_role.lambda_auth_check.id
  policy = data.aws_iam_policy_document.lambda_auth_check.json
}
