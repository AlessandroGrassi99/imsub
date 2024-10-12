resource "terraform_data" "build_lambda_state_deleted" {
  provisioner "local-exec" {
    command = <<EOT
      cd ${path.module}/state_deleted/;
      echo 'Cleaning ${local.resource_name_prefix}-lambda-state-deleted'
      npm run clean
      echo 'Building ${local.resource_name_prefix}-lambda-state-deleted'
      npm run build
      echo 'Built ${local.resource_name_prefix}-lambda-state-deleted'
    EOT
  }

  triggers_replace = [
    filemd5("${path.module}/state_deleted/index.ts"),
  ]
}

resource "aws_lambda_function" "state_deleted" {
  function_name = "${local.resource_name_prefix}-lambda-state-deleted"
  handler = "index.handler"
  runtime = "nodejs20.x"
  publish = true
  role = aws_iam_role.lambda_state_deleted.arn

  filename         = "${path.module}/state_deleted/dist/index.zip"
  source_code_hash = filemd5("${path.module}/state_deleted/dist/index.zip")
  timeout          = 5
  
  environment {
    variables = {
      TELEGRAM_BOT_TOKEN      = local.telegram_bot_token
    }
  }

  depends_on = [terraform_data.build_lambda_state_deleted]
}

# resource "aws_lambda_provisioned_concurrency_config" "webhook" {
#   function_name                     = aws_lambda_function.webhook.function_name
#   provisioned_concurrent_executions = 1
#   qualifier                         = aws_lambda_function.webhook.version

#   depends_on = [ aws_lambda_function.webhook ]
# }

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