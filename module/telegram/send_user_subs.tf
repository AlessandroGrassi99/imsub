resource "aws_sqs_queue" "send_user_subs" {
  name = "${local.resource_name_prefix}-sqs-send-user-subs"
}

resource "aws_sfn_state_machine" "send_user_subs" {
  name     = "${local.resource_name_prefix}-sfn-send-user-subs"
  role_arn = aws_iam_role.sfn_send_user_subs.arn

  definition = templatefile("${path.module}/send_user_subs.sfn.json", {
    dyanamodb_table_creators_name = data.aws_dynamodb_table.creators.name,
    lambda_get_user_subs_arn      = data.aws_lambda_function.get_user_subs.arn,
    lambda_send_user_subs_arn     = aws_lambda_function.send_user_subs.arn,
  })

  ### Expected input
  # {
  #   "user_id": "18121313",
  #   "message_id": "460",       (Optional)
  #   "twitch_id": "101319792",
  #   "access_token": "fhasfjakdhflkjdbrhj3r1" (Optional) 
  # }
}

resource "aws_iam_role" "sfn_send_user_subs" {
  name               = "${local.resource_name_prefix}-sfn-send-user-subs-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role_policy.json
}

data "aws_iam_policy_document" "sfn_send_user_subs" {
  statement {
    actions   = ["dynamodb:Scan"]
    resources = [data.aws_dynamodb_table.creators.arn]
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

  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [
      data.aws_lambda_function.check_user_auth.arn,
      data.aws_lambda_function.get_user_subs.arn,
      aws_lambda_function.send_user_subs.arn
    ]
    effect = "Allow"
  }
}

resource "aws_iam_role_policy" "sfn_send_user_subs" {
  name   = "${local.resource_name_prefix}-sfn-send-user-subs-role-policy"
  role   = aws_iam_role.sfn_send_user_subs.id
  policy = data.aws_iam_policy_document.sfn_send_user_subs.json
}

###
### Lambda
###

resource "terraform_data" "builder_lambda_send_user_subs" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_send_user_subs/"
    command     = "npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_send_user_subs/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_send_user_subs/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_send_user_subs/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_send_user_subs/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_send_user_subs" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_send_user_subs/dist/"
  output_path = "${path.module}/lambda_send_user_subs/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_send_user_subs
  ]
}

resource "aws_lambda_function" "send_user_subs" {
  function_name = "${local.resource_name_prefix}-lambda-send-user-subs"

  handler = "index.handler"
  runtime = "nodejs20.x"
  publish = true
  role    = aws_iam_role.lambda_send_user_subs.arn

  filename         = data.archive_file.archiver_lambda_send_user_subs.output_path
  source_code_hash = data.archive_file.archiver_lambda_send_user_subs.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TELEGRAM_BOT_TOKEN = local.telegram_bot_token
    }
  }

  depends_on = [
    terraform_data.builder_lambda_send_user_subs,
    data.archive_file.archiver_lambda_send_user_subs
  ]
}

resource "aws_iam_role" "lambda_send_user_subs" {
  name               = "${local.resource_name_prefix}-lambda-send-user-subs-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_send_user_subs" {
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

resource "aws_iam_role_policy" "lambda_send_user_subs" {
  name   = "${local.resource_name_prefix}-lambda-send-user-subs-role-policy"
  role   = aws_iam_role.lambda_send_user_subs.id
  policy = data.aws_iam_policy_document.lambda_send_user_subs.json
}

###
### Pipes
###

resource "aws_pipes_pipe" "send_user_subs_pipe" {
  name     = "${local.resource_name_prefix}-pipe-send-user-subs"
  role_arn = aws_iam_role.eventbridge_pipe_send_user_subs.arn

  source = aws_sqs_queue.send_user_subs.arn
  source_parameters {
    sqs_queue_parameters {
      batch_size                         = 10
      maximum_batching_window_in_seconds = 0
    }
  }

  target = aws_sfn_state_machine.send_user_subs.arn
  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }
}

data "aws_iam_policy_document" "pipes_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_pipe_send_user_subs" {
  name               = "${local.resource_name_prefix}-eventbridge-pipe-send-user-subs-role"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume_role_policy.json
}

data "aws_iam_policy_document" "eventbridge_pipe_send_user_subs" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.send_user_subs.arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.send_user_subs.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "eventbridge_pipe_send_user_subs" {
  name   = "${local.resource_name_prefix}-eventbridge-pipe-send-user-subs-role-policy"
  role   = aws_iam_role.eventbridge_pipe_send_user_subs.id
  policy = data.aws_iam_policy_document.eventbridge_pipe_send_user_subs.json
}