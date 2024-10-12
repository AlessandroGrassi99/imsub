resource "terraform_data" "builder_lambda_state_deleted" {
  provisioner "local-exec" {
    working_dir = "${path.module}/state_deleted/"
    command = "npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/state_deleted/index.ts"),
    package  = filebase64sha256("${path.module}/state_deleted/package.json"),
    lock     = filebase64sha256("${path.module}/state_deleted/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/state_deleted/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_state_deleted" {
  type        = "zip"
  source_dir  = "${path.module}/state_deleted/dist/"
  output_path = "${path.module}/state_deleted/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_state_deleted
  ]
}

resource "aws_lambda_function" "state_deleted" {
  function_name = "${local.resource_name_prefix}-lambda-state-deleted"
  handler = "index.handler"
  runtime = "nodejs20.x"
  publish = true
  role = aws_iam_role.lambda_state_deleted.arn

  filename         = data.archive_file.archiver_lambda_state_deleted.output_path
  source_code_hash = data.archive_file.archiver_lambda_state_deleted.output_base64sha256
  timeout          = 5
  
  environment {
    variables = {
      TELEGRAM_BOT_TOKEN      = local.telegram_bot_token
    }
  }

  depends_on = [
    terraform_data.builder_lambda_state_deleted,
    data.archive_file.archiver_lambda_state_deleted
  ]
}

resource "aws_iam_role" "lambda_state_deleted" {
  name               = "${local.resource_name_prefix}-lambda-state-deleted-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_state_deleted" {
  statement {
    actions = [
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:DescribeStream",
      "dynamodb:ListStreams",
    ]
    resources = [
      data.aws_dynamodb_table.auth_states.stream_arn,
    ]
    effect = "Allow"
  }

  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:Query",
    ]
    resources = [
      data.aws_dynamodb_table.auth_states.arn,
      "${data.aws_dynamodb_table.auth_states.arn}/*"
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

resource "aws_iam_role_policy" "lambda_state_deleted" {
  name   = "${local.resource_name_prefix}-lambda-state-deleted-role-policy"
  role   = aws_iam_role.lambda_state_deleted.id
  policy = data.aws_iam_policy_document.lambda_state_deleted.json
}

resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn  = data.aws_dynamodb_table.auth_states.stream_arn
  function_name     = aws_lambda_function.state_deleted.function_name
  starting_position = "LATEST"

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["REMOVE"]
      })
    }
  }
}